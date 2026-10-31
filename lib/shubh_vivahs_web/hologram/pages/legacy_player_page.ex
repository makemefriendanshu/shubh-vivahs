defmodule ShubhVivahsWeb.Hologram.Pages.LegacyPlayerPage do
  @moduledoc """
  Keeps old `/premiere/<id>` player links (shared, bookmarked, in browser
  history) working: redirects to the movie's readable URL,
  `/premiere/<uploader>/<slug>` (see `ShubhVivahs.MovieSlug`). A private
  movie redirects signed-out visitors to Premiere Hall instead, so an old
  link can't reveal its title.
  """

  use Hologram.Page

  route "/premiere/:id"
  param :id, :string

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  # The redirect itself happens in middleware (see PlayerUrlRedirect), so
  # this page never actually renders.
  middleware ShubhVivahsWeb.Hologram.Middleware.PlayerUrlRedirect, mode: :legacy

  def init(_params, component, server), do: {component, server}

  def template do
    ~HOLO"""
    <p class="p-6 text-center text-base-content/70">Redirecting…</p>
    """
  end
end
