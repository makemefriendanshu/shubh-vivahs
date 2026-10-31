defmodule ShubhVivahsWeb.MovieThumbnailController do
  use ShubhVivahsWeb, :controller

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.MovieThumbnail
  alias ShubhVivahs.Repo
  alias ShubhVivahsWeb.MovieAccess

  def show(conn, %{"id" => id}) do
    with %Movie{} = movie <- Repo.get(Movie, id),
         true <- MovieAccess.viewable?(conn, movie) do
      path =
        if MovieThumbnail.thumbnail_ready?(movie),
          do: MovieThumbnail.thumbnail_path(movie),
          else: MovieThumbnail.generate!(movie)

      # Public + a day so Cloudflare (and browsers) serve repeat views
      # without touching this server; a movie's poster frame never changes.
      # Private movies stay out of Cloudflare's cache, or a signed-in
      # viewer's request would leak the poster to everyone after them.
      cache = if movie.public, do: "public", else: "private"

      conn
      |> put_resp_content_type("image/jpeg", nil)
      |> put_resp_header("cache-control", "#{cache}, max-age=86400")
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end
end
