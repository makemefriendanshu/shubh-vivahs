defmodule ShubhVivahsWeb.LibraryMediaController do
  @moduledoc """
  Serves media library files (see `ShubhVivahs.Library`) — the playable
  file, its WebVTT subtitles, and its poster thumbnail. Signed-in users
  only (routed through `Plugs.RequireAuthenticatedUser`), and sent as
  `private` so Cloudflare never caches them for anyone else.
  """

  use ShubhVivahsWeb, :controller

  alias ShubhVivahs.Library
  alias ShubhVivahs.Library.MediaItem
  alias ShubhVivahsWeb.FileStreaming

  @content_types %{
    ".mp4" => "video/mp4",
    ".mp3" => "audio/mpeg",
    ".m4a" => "audio/mp4",
    ".aac" => "audio/aac",
    ".ogg" => "audio/ogg",
    ".opus" => "audio/ogg",
    ".flac" => "audio/flac",
    ".wav" => "audio/wav"
  }

  def show(conn, %{"id" => id}) do
    with %MediaItem{} = item <- Library.get_item(id),
         path when is_binary(path) <- Library.media_path(item),
         true <- File.regular?(path) do
      content_type =
        Map.get(@content_types, Path.extname(path), "application/octet-stream")

      conn
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> FileStreaming.send_ranged(path, content_type)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def subtitles(conn, %{"id" => id}) do
    with %MediaItem{} = item <- Library.get_item(id),
         path when is_binary(path) <- Library.subtitle_path(item),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type("text/vtt")
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def thumbnail(conn, %{"id" => id}) do
    with %MediaItem{} = item <- Library.get_item(id),
         path <- Library.thumbnail_path(item),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type("image/jpeg", nil)
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end
end
