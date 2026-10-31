defmodule ShubhVivahsWeb.PhotoFileController do
  @moduledoc """
  Serves a photo's thumbnail, web-sized copy, and original (see
  `ShubhVivahs.Photos`) under `/photos/<id>/…`, with the same rule as film
  files (`MovieAccess`): anyone for a public album, signed-in users for a
  private one. Public albums' files are cacheable by Cloudflare (it caches
  by the .jpg extension); private ones are not.
  """

  use ShubhVivahsWeb, :controller

  alias ShubhVivahs.Photos
  alias ShubhVivahs.Photos.{Album, Face, Photo}
  alias ShubhVivahsWeb.MovieAccess

  def thumb(conn, %{"id" => id}), do: serve(conn, id, &Photos.thumb_path/1, nil)
  def web(conn, %{"id" => id}), do: serve(conn, id, &Photos.web_path/1, nil)
  def original(conn, %{"id" => id}), do: serve(conn, id, &Photos.original_path/1, :download)

  @doc """
  One batch of an album's photos for the album page's infinite scroll,
  `/photos/albums/<id>/page.json?page=N` (optionally `&person=<face id>`):
  `{"photos": [{"id", "index", "thumb_url"}]}`.
  """
  def page(conn, %{"id" => id} = params) do
    with {album_id, ""} <- Integer.parse(id),
         %Album{} = album <- Photos.get_album(album_id),
         true <- MovieAccess.viewable?(conn, album),
         {page, ""} when page >= 1 <- Integer.parse(Map.get(params, "page", "1")),
         {:ok, person_id} <- person_param(album, params["person"]) do
      per_page = Photos.per_page()

      photos =
        album
        |> Photos.photo_page(page, per_page, person_id)
        |> Enum.with_index((page - 1) * per_page)
        |> Enum.map(fn {photo, index} ->
          %{id: photo.id, index: index, thumb_url: Photos.thumb_url(photo)}
        end)

      cache = if album.public, do: "public", else: "private"

      conn
      |> put_resp_header("cache-control", "#{cache}, max-age=60")
      |> json(%{photos: photos})
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp person_param(_album, blank) when blank in [nil, ""], do: {:ok, nil}

  defp person_param(album, value) do
    with {id, ""} <- Integer.parse(value),
         %{id: id} <- Photos.album_person(album, id) do
      {:ok, id}
    else
      _ -> :error
    end
  end

  @doc "A recognised person's cropped portrait, `/photos/faces/<face id>/portrait.jpg`."
  def face(conn, %{"id" => id}) do
    with %Face{} = face <- Photos.get_face(id),
         %Album{} = album <- Photos.get_album(face.album_id),
         true <- MovieAccess.viewable?(conn, album),
         path = Photos.face_path(face),
         true <- File.regular?(path) do
      send_jpeg(conn, path, album)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp serve(conn, id, path_fun, disposition) do
    with %Photo{} = photo <- Photos.get_photo(id),
         %Album{} = album <- Photos.get_album(photo.album_id),
         true <- MovieAccess.viewable?(conn, album),
         path = path_fun.(photo),
         true <- File.regular?(path) do
      conn
      |> then(fn conn ->
        if disposition == :download,
          do:
            put_resp_header(
              conn,
              "content-disposition",
              ~s(attachment; filename="#{photo.original_name}")
            ),
          else: conn
      end)
      |> send_jpeg(path, album)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp send_jpeg(conn, path, album) do
    cache = if album.public, do: "public", else: "private"

    conn
    |> put_resp_content_type("image/jpeg", nil)
    |> put_resp_header("cache-control", "#{cache}, max-age=604800")
    |> send_file(200, path)
  end
end
