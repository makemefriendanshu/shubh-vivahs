defmodule ShubhVivahsWeb.LibraryMediaControllerTest do
  use ShubhVivahsWeb.ConnCase

  alias ShubhVivahs.Accounts

  test "GET /library/media/:id redirects visitors who aren't signed in", %{conn: conn} do
    conn = get(conn, ~p"/library/media/1/file")
    assert redirected_to(conn) == "/login"
  end

  test "GET /library/media/:id 404s for an unknown item when signed in", %{conn: conn} do
    conn = conn |> log_in() |> get(~p"/library/media/999999/file")
    assert conn.status == 404
  end

  test "GET /library/media/:id/subtitles.vtt 404s for an unknown item", %{conn: conn} do
    conn = conn |> log_in() |> get(~p"/library/media/999999/subtitles.vtt")
    assert conn.status == 404
  end

  defp log_in(conn) do
    {:ok, user} =
      Accounts.seed_user(%{
        name: "Member",
        email: "library-media-test@example.com",
        password: "correcthorsebatterystaple"
      })

    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session(:hologram_user_id, user.id)
  end
end
