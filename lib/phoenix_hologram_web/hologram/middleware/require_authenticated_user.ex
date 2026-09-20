defmodule PhoenixHologramWeb.Hologram.Middleware.RequireAuthenticatedUser do
  @moduledoc """
  Gates a page/command behind login: redirects to LoginPage unless
  `server.user_id` (set via `put_user_id/2` at login, see LoginPage and
  RegisterPage) names an account that still exists. On success, stashes
  the loaded user under `:current_user` so `init/3` and commands don't
  each have to re-fetch it.
  """

  use Hologram.Middleware

  alias PhoenixHologram.Accounts
  alias PhoenixHologramWeb.Hologram.Pages.LoginPage

  @impl Hologram.Middleware
  def call(server, _opts) do
    with user_id when not is_nil(user_id) <- server.user_id,
         %Accounts.User{} = user <- Accounts.get_user(user_id) do
      put_stash(server, :current_user, user)
    else
      _not_logged_in -> put_redirect(server, LoginPage)
    end
  end
end
