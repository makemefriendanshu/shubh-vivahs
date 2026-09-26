defmodule PhoenixHologramWeb.Hologram.Middleware.RequireSuperuser do
  @moduledoc """
  Gates the superuser-only demo content — admin movie management,
  analytics, and promo-request review — behind the seeded superuser
  account (see `PhoenixHologram.Accounts.seed_user/1` and
  `priv/repo/seeds.exs`). Composes on top of `RequireAuthenticatedUser`:
  an anonymous visitor is sent to LoginPage, a logged-in non-superuser is
  sent to DashboardPage instead of getting a bare 403.
  """

  use Hologram.Middleware

  alias PhoenixHologram.Accounts
  alias PhoenixHologramWeb.Hologram.Middleware.RequireAuthenticatedUser
  alias PhoenixHologramWeb.Hologram.Pages.DashboardPage

  middleware RequireAuthenticatedUser
  middleware :require_superuser

  def require_superuser(server, _opts) do
    if Accounts.superuser?(get_stash(server, :current_user)) do
      server
    else
      put_redirect(server, DashboardPage)
    end
  end
end
