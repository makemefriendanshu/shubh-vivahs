defmodule ShubhVivahsWeb.VideoController do
  use ShubhVivahsWeb, :controller

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.Repo
  alias ShubhVivahs.VideoPreview
  alias ShubhVivahs.VideoSegments

  @content_types %{
    ".mp4" => "video/mp4",
    ".mov" => "video/quicktime",
    ".webm" => "video/webm",
    ".mkv" => "video/x-matroska",
    ".m4v" => "video/x-m4v"
  }

  def show(conn, %{"id" => id} = params) do
    with %Movie{} = movie <- Repo.get(Movie, id),
         path <- VideoPreview.resolve_quality(movie, params["quality"]),
         true <- File.regular?(path) do
      stream_video(conn, path)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def download(conn, %{"id" => id} = params) do
    with %Movie{} = movie <- Repo.get(Movie, id),
         path <- VideoPreview.resolve_quality(movie, params["quality"]),
         true <- File.regular?(path) do
      conn
      |> put_attachment_header(download_filename(movie, path))
      |> stream_video(path)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def download_chunk(conn, %{"id" => id, "part" => part_str} = params) do
    with %Movie{} = movie <- Repo.get(Movie, id),
         {part, ""} <- Integer.parse(part_str),
         quality <- VideoPreview.normalize_quality(movie, params["quality"]),
         segments <- VideoSegments.ensure_generated!(movie, quality),
         true <- part in 1..length(segments) do
      path = Enum.at(segments, part - 1)

      conn
      |> put_resp_content_type(content_type_for(path), nil)
      |> put_attachment_header(download_filename(movie, path, part, length(segments)))
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def play_chunk(conn, %{"id" => id, "part" => part_str} = params) do
    with %Movie{} = movie <- Repo.get(Movie, id),
         {part, ""} <- Integer.parse(part_str),
         quality <- VideoPreview.normalize_quality(movie, params["quality"]),
         segments <- VideoSegments.ensure_generated!(movie, quality),
         true <- part in 1..length(segments) do
      stream_video(conn, Enum.at(segments, part - 1))
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp download_filename(movie, path) do
    "#{safe_title(movie)}#{Path.extname(path)}"
  end

  defp download_filename(movie, path, part, total) do
    padded_part = part |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{safe_title(movie)}.part#{padded_part}-of-#{total}#{Path.extname(path)}"
  end

  defp safe_title(movie) do
    (movie.title || "movie-#{movie.id}")
    |> String.replace(~r/[^A-Za-z0-9_\-]+/, "_")
  end

  defp put_attachment_header(conn, filename) do
    put_resp_header(conn, "content-disposition", ~s(attachment; filename="#{filename}"))
  end

  defp content_type_for(path) do
    Map.get(
      @content_types,
      path |> Path.extname() |> String.downcase(),
      "application/octet-stream"
    )
  end

  defp stream_video(conn, path) do
    %{size: size} = File.stat!(path)

    conn =
      conn
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_content_type(content_type_for(path), nil)

    case get_req_header(conn, "range") do
      ["bytes=" <> range] -> send_range(conn, path, size, range)
      _ -> send_file(conn, 200, path)
    end
  end

  defp send_range(conn, path, size, range) do
    {range_start, range_end} = parse_range(range, size)
    length = range_end - range_start + 1

    conn
    |> put_resp_header("content-range", "bytes #{range_start}-#{range_end}/#{size}")
    |> send_file(206, path, range_start, length)
  end

  defp parse_range(range, size) do
    case String.split(range, "-") do
      [start_str, ""] ->
        {String.to_integer(start_str), size - 1}

      [start_str, end_str] ->
        {String.to_integer(start_str), min(String.to_integer(end_str), size - 1)}

      _ ->
        {0, size - 1}
    end
  end
end
