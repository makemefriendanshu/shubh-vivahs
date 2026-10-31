defmodule ShubhVivahsWeb.PhotoFileControllerTest do
  use ShubhVivahsWeb.ConnCase

  alias ShubhVivahs.Accounts
  alias ShubhVivahs.Photos
  alias ShubhVivahs.Photos.{Album, Photo}
  alias ShubhVivahs.Repo

  setup do
    File.rm_rf!(Photos.storage_dir())
    :ok
  end

  defp photo!(public?) do
    album = Repo.insert!(%Album{title: "Album", slug: "album-#{public?}", public: public?})

    photo =
      Repo.insert!(%Photo{
        album_id: album.id,
        original_name: "IMG_1.jpg",
        original_path: "#{album.id}/originals/00001-IMG_1.jpg",
        source_path: "/src/#{album.id}/IMG_1.jpg",
        position: 1
      })

    for path <- [Photos.original_path(photo), Photos.web_path(photo), Photos.thumb_path(photo)] do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "jpeg bytes")
    end

    photo
  end

  test "public album photos are served to anyone", %{conn: conn} do
    photo = photo!(true)
    conn = get(conn, "/photos/#{photo.id}/thumb.jpg")
    assert conn.status == 200
    assert conn.resp_body == "jpeg bytes"
  end

  test "private album photos 404 for signed-out visitors", %{conn: conn} do
    photo = photo!(false)
    assert get(conn, "/photos/#{photo.id}/web.jpg").status == 404
  end

  test "signed-in members can download private originals", %{conn: conn} do
    photo = photo!(false)
    conn = conn |> log_in() |> get("/photos/#{photo.id}/original.jpg")
    assert conn.status == 200
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "IMG_1.jpg"
  end

  test "portraits follow their album's visibility", %{conn: conn} do
    photo = photo!(false)

    face =
      Repo.insert!(%ShubhVivahs.Photos.Face{album_id: photo.album_id, embedding: [0.1, 0.2]})

    path = Photos.face_path(face)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "portrait")

    assert get(conn, "/photos/faces/#{face.id}/portrait.jpg").status == 404

    assert conn |> log_in() |> get("/photos/faces/#{face.id}/portrait.jpg") |> response(200) ==
             "portrait"
  end

  test "page.json lists a batch of a visible album's photos", %{conn: conn} do
    photo = photo!(true)
    body = conn |> get("/photos/albums/#{photo.album_id}/page.json?page=1") |> json_response(200)

    assert body == %{
             "photos" => [
               %{"id" => photo.id, "index" => 0, "thumb_url" => "/photos/#{photo.id}/thumb.jpg"}
             ]
           }

    assert get(conn, "/photos/albums/#{photo.album_id}/page.json?page=2") |> json_response(200) ==
             %{"photos" => []}
  end

  test "page.json 404s for private albums, bad pages and unknown people", %{conn: conn} do
    private = photo!(false)
    assert get(conn, "/photos/albums/#{private.album_id}/page.json?page=1").status == 404

    public = photo!(true)
    assert get(conn, "/photos/albums/#{public.album_id}/page.json?page=0").status == 404

    assert get(conn, "/photos/albums/#{public.album_id}/page.json?page=1&person=999999").status ==
             404
  end

  test "unknown photos 404", %{conn: conn} do
    assert get(conn, "/photos/999999/thumb.jpg").status == 404
  end

  defp log_in(conn) do
    {:ok, user} =
      Accounts.seed_user(%{
        name: "Member",
        email: "photo-file-test@example.com",
        password: "correcthorsebatterystaple"
      })

    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session(:hologram_user_id, user.id)
  end
end
