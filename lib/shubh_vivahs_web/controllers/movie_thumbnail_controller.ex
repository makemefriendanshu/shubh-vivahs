defmodule ShubhVivahsWeb.MovieThumbnailController do
  use ShubhVivahsWeb, :controller

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.MovieThumbnail
  alias ShubhVivahs.Repo

  def show(conn, %{"id" => id}) do
    case Repo.get(Movie, id) do
      %Movie{} = movie ->
        path =
          if MovieThumbnail.thumbnail_ready?(movie),
            do: MovieThumbnail.thumbnail_path(movie),
            else: MovieThumbnail.generate!(movie)

        conn
        |> put_resp_content_type("image/jpeg", nil)
        |> send_file(200, path)

      nil ->
        send_resp(conn, 404, "Not found")
    end
  end
end
