defmodule ShubhVivahsWeb.VideoController do
  use ShubhVivahsWeb, :controller

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.FocusScenes
  alias ShubhVivahs.Repo
  alias ShubhVivahs.VideoPreview
  alias ShubhVivahs.VideoSegments
  alias ShubhVivahsWeb.FileStreaming
  alias ShubhVivahsWeb.MovieAccess

  @content_types %{
    ".mp4" => "video/mp4",
    ".mov" => "video/quicktime",
    ".webm" => "video/webm",
    ".mkv" => "video/x-matroska",
    ".m4v" => "video/x-m4v"
  }

  def show(conn, %{"id" => id} = params) do
    with %Movie{} = movie <- Repo.get(Movie, id),
         true <- MovieAccess.viewable?(conn, movie),
         path <- stream_path(movie, params),
         true <- File.regular?(path) do
      stream_video(conn, path)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  @doc """
  The movie's "Who's in focus?" scenes as JSON, fetched once by the
  player's inline script (see `ShubhVivahs.FocusScenes`).
  """
  def scenes(conn, %{"id" => id}) do
    with %Movie{} = movie <- Repo.get(Movie, id),
         true <- MovieAccess.viewable?(conn, movie) do
      conn
      |> put_resp_header("cache-control", "private, no-cache")
      |> json(FocusScenes.scenes(movie, nil))
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  # ?lang=<code> picks one of a library item's extra audio-language copies
  # (always original quality; see Library.audio_versions/1), otherwise the
  # usual ?quality= tiers of the main file.
  defp stream_path(movie, %{"lang" => lang} = params) when is_binary(lang) and lang != "" do
    with %ShubhVivahs.Library.MediaItem{} = item <- ShubhVivahs.Library.get_by_movie_id(movie.id),
         %{path: path} <-
           Enum.find(ShubhVivahs.Library.audio_versions(item), &(&1.language == lang)) do
      path
    else
      _ -> VideoPreview.resolve_quality(movie, params["quality"])
    end
  end

  defp stream_path(movie, params), do: VideoPreview.resolve_quality(movie, params["quality"])

  def download(conn, %{"id" => id} = params) do
    with %Movie{} = movie <- Repo.get(Movie, id),
         true <- MovieAccess.viewable?(conn, movie),
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
         true <- MovieAccess.viewable?(conn, movie),
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
         true <- MovieAccess.viewable?(conn, movie),
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
    FileStreaming.send_ranged(conn, path, content_type_for(path))
  end
end
