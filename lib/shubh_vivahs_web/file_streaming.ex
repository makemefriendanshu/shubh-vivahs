defmodule ShubhVivahsWeb.FileStreaming do
  @moduledoc """
  Sends a media file with HTTP Range support, so browsers can seek
  within a video/song without downloading everything before the seek
  point. Shared by `VideoController` and `LibraryMediaController`.
  """

  import Plug.Conn

  @spec send_ranged(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  def send_ranged(conn, path, content_type) do
    %{size: size} = File.stat!(path)

    conn =
      conn
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_content_type(content_type, nil)

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
