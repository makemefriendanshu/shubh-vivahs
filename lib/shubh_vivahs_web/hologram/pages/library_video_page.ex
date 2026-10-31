defmodule ShubhVivahsWeb.Hologram.Pages.LibraryVideoPage do
  @moduledoc """
  Media library player: `/library/<uploader>/<slug>` (series episodes and
  movies). Same page as the wedding gallery player — see
  `ShubhVivahsWeb.Hologram.PlayerPageBase`.
  """

  use ShubhVivahsWeb.Hologram.PlayerPageBase, route: "/library/:uploader/:name", section: :library
end
