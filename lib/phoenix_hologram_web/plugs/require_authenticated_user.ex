defmodule PhoenixHologramWeb.Plugs.RequireAuthenticatedUser do
  @moduledoc """
  Gates plain (non-Hologram) endpoints that need a logged-in account —
  currently just `AccountAvatarController`'s upload action — behind the
  same login `PhoenixHologramWeb.Hologram.Middleware.RequireAuthenticatedUser`
  uses. Assigns the loaded user to `conn.assigns.current_user` since these
  routes sit outside Hologram's own request pipeline and never see a
  `%Hologram.Server{}` stash. Mirrors `Plugs.RequireSuperuser`, minus the
  superuser check.
  """

  import Plug.Conn

  alias PhoenixHologram.Accounts

  @spec init(keyword) :: keyword
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword) :: Plug.Conn.t()
  def call(conn, _opts) do
    with user_id when not is_nil(user_id) <- Hologram.Runtime.Session.get_user_id(conn),
         %Accounts.User{} = user <- Accounts.get_user(user_id) do
      assign(conn, :current_user, user)
    else
      _not_logged_in ->
        conn
        |> Phoenix.Controller.redirect(to: "/login")
        |> halt()
    end
  end
end
