defmodule ShubhVivahsWeb.VideoControllerTest do
  use ShubhVivahsWeb.ConnCase

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.Repo

  test "private movies' video and thumbnail 404 for visitors who aren't signed in", %{conn: conn} do
    movie =
      Repo.insert!(%Movie{path: "/nonexistent/private.mp4", title: "Private", public: false})

    assert get(conn, ~p"/premiere/videos/#{movie.id}/stream").status == 404
    assert get(conn, ~p"/premiere/videos/#{movie.id}/thumbnail.jpg").status == 404
    assert get(conn, ~p"/premiere/videos/#{movie.id}/download").status == 404
  end
end
