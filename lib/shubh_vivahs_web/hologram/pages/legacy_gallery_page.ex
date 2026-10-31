defmodule ShubhVivahsWeb.Hologram.Pages.LegacyGalleryPage do
  @moduledoc """
  `/premiere`, the wedding gallery's address before it moved to `/gallery`
  (PremierePage): redirects there.
  """

  use Hologram.Page

  route "/premiere"

  # The redirect happens in middleware (see PlayerUrlRedirect), so this page
  # never actually renders.
  middleware ShubhVivahsWeb.Hologram.Middleware.PlayerUrlRedirect, mode: :gallery_index

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server), do: {component, server}

  def template do
    ~HOLO"""
    <p class="p-6 text-center text-base-content/70">Redirecting…</p>
    """
  end
end
