defmodule ShubhVivahsWeb.FaceThumbnailControllerTest do
  use ShubhVivahsWeb.ConnCase

  alias ShubhVivahs.Accounts

  test "GET /admin/faces/:id/thumbnail 403s for a visitor who isn't a superuser", %{conn: conn} do
    conn = get(conn, ~p"/admin/faces/999999/thumbnail")
    assert conn.status == 403
  end

  test "GET /admin/faces/:id/thumbnail 404s for an unknown face when signed in as a superuser", %{
    conn: conn
  } do
    conn = conn |> log_in_superuser() |> get(~p"/admin/faces/999999/thumbnail")
    assert conn.status == 404
  end

  defp log_in_superuser(conn) do
    {:ok, user} =
      Accounts.seed_user(%{
        name: "Admin",
        email: "admin-face-thumb-test@example.com",
        password: "correcthorsebatterystaple",
        is_superuser: true
      })

    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session(:hologram_user_id, user.id)
  end

  test "GET /premiere/faces/:id/thumbnail.jpg follows the movie's visibility", %{conn: conn} do
    private =
      ShubhVivahs.Repo.insert!(%ShubhVivahs.FaceDetection.Movie{path: "/x/p.mp4", public: false})

    face =
      ShubhVivahs.Repo.insert!(%ShubhVivahs.FaceDetection.Face{
        movie_id: private.id,
        embedding: [0.1, 0.2]
      })

    assert get(conn, ~p"/premiere/faces/#{face.id}/thumbnail.jpg").status == 404
    assert get(conn, ~p"/premiere/faces/999999/thumbnail.jpg").status == 404
  end

  test "old admin URL shapes redirect for superusers", %{conn: conn} do
    movie =
      ShubhVivahs.Repo.insert!(%ShubhVivahs.FaceDetection.Movie{
        path: "/x/r.mp4",
        title: "Reception",
        slug: "reception"
      })

    conn = log_in_superuser(conn)

    assert redirected_to(get(conn, "/admin/movies/#{movie.id}")) == "/admin/shubhvivahs/reception"
    assert redirected_to(get(conn, "/admin/movies/999999")) == "/admin"

    assert redirected_to(get(conn, "/admin/analytics/export.csv?days=7")) ==
             "/admin/analytics.csv?days=7"
  end

  test "old admin URL shapes stay superuser-only", %{conn: conn} do
    assert get(conn, "/admin/movies/1").status == 403
  end
end
