defmodule ShubhVivahsWeb.FaceThumbnailController do
  use ShubhVivahsWeb, :controller

  alias ShubhVivahs.FaceDetection.Face
  alias ShubhVivahs.FaceThumbnail
  alias ShubhVivahs.Repo
  alias ShubhVivahsWeb.MovieAccess

  @doc "Admin pages' face thumbnails (`/admin/faces/:id/thumbnail`, superusers only)."
  def show(conn, %{"id" => id}) do
    case Repo.get(Face, id) do
      %Face{} = face -> send_thumbnail(conn, face, "private, max-age=86400")
      nil -> send_resp(conn, 404, "Not found")
    end
  end

  @doc """
  Viewer-facing face thumbnails (`/premiere/faces/:id/thumbnail.jpg`) —
  the "Who's in focus?" panel and the Science of Focus page — with the same
  access rule as the face's movie (`MovieAccess`): anyone for a public
  movie, signed-in users for a private one. Public ones are cacheable by
  Cloudflare (it caches by the .jpg extension); a face crop never changes.
  """
  def public_show(conn, %{"id" => id}) do
    with %Face{} = face <- Repo.get(Face, id),
         face = Repo.preload(face, :movie),
         true <- MovieAccess.viewable?(conn, face.movie) do
      cache = if face.movie.public, do: "public", else: "private"
      send_thumbnail(conn, face, "#{cache}, max-age=86400")
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp send_thumbnail(conn, face, cache_control) do
    face = Repo.preload(face, [:movie, :detections])

    path =
      if FaceThumbnail.thumbnail_ready?(face),
        do: FaceThumbnail.thumbnail_path(face),
        else: FaceThumbnail.generate!(face)

    conn
    |> put_resp_content_type("image/jpeg", nil)
    |> put_resp_header("cache-control", cache_control)
    |> send_file(200, path)
  end
end
