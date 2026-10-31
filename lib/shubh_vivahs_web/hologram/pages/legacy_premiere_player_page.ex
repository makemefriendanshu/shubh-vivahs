defmodule ShubhVivahsWeb.Hologram.Pages.LegacyPremierePlayerPage do
  @moduledoc """
  `/premiere/<uploader>/<slug>`, the player address before it split into
  `/gallery/…` (wedding films) and `/library/…` (media library): redirects
  to wherever the movie lives now (see `ShubhVivahs.MovieSlug.path/1`).
  Also catches the old 3-segment stream URL `/premiere/videos/<id>`.
  """

  use Hologram.Page

  route "/premiere/:uploader/:name"
  param :uploader, :string
  param :name, :string

  # The redirect happens in middleware (see PlayerUrlRedirect), so this page
  # never actually renders.
  middleware ShubhVivahsWeb.Hologram.Middleware.PlayerUrlRedirect, mode: :premiere_legacy

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server), do: {component, server}

  def template do
    ~HOLO"""
    <p class="p-6 text-center text-base-content/70">Redirecting…</p>
    """
  end
end
