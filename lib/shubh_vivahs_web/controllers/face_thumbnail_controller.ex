defmodule ShubhVivahsWeb.FaceThumbnailController do
  use ShubhVivahsWeb, :controller

  alias ShubhVivahs.FaceDetection.Face
  alias ShubhVivahs.FaceThumbnail
  alias ShubhVivahs.Repo

  def show(conn, %{"id" => id}) do
    case Repo.get(Face, id) do
      %Face{} = face ->
        face = Repo.preload(face, [:movie, :detections])

        path =
          if FaceThumbnail.thumbnail_ready?(face),
            do: FaceThumbnail.thumbnail_path(face),
            else: FaceThumbnail.generate!(face)

        conn
        |> put_resp_content_type("image/jpeg", nil)
        |> send_file(200, path)

      nil ->
        send_resp(conn, 404, "Not found")
    end
  end
end
