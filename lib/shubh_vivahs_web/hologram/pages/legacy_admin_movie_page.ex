defmodule ShubhVivahsWeb.Hologram.Pages.LegacyAdminMoviePage do
  @moduledoc """
  Keeps the earlier `/admin/movies/<uploader>/<slug>` links working:
  redirects to the shorter `/admin/<uploader>/<slug>` (see
  `ShubhVivahs.MovieSlug`), or to the admin film list for an unknown movie.
  (The even older `/admin/movies/<id>` lands on AdminMoviePage's route and
  is redirected there.) Superusers only, like the page it points to.
  """

  use Hologram.Page

  alias ShubhVivahsWeb.Hologram.Middleware.RequireSuperuser

  route "/admin/movies/:uploader/:name"
  param :uploader, :string
  param :name, :string

  # The redirect happens in middleware (see PlayerUrlRedirect), so this page
  # never actually renders.
  middleware RequireSuperuser
  middleware ShubhVivahsWeb.Hologram.Middleware.PlayerUrlRedirect, mode: :admin_legacy

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server), do: {component, server}

  def template do
    ~HOLO"""
    <p class="p-6 text-center text-base-content/70">Redirecting…</p>
    """
  end
end
