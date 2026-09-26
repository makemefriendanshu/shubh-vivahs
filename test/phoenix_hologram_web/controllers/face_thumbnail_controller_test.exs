defmodule PhoenixHologramWeb.FaceThumbnailControllerTest do
  use PhoenixHologramWeb.ConnCase

  alias PhoenixHologram.Accounts

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
end
