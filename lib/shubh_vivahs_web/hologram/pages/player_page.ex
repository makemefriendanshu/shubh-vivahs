defmodule ShubhVivahsWeb.Hologram.Pages.PlayerPage do
  @moduledoc """
  Wedding gallery player: `/gallery/<uploader>/<slug>`. See
  `ShubhVivahsWeb.Hologram.PlayerPageBase` for the page itself.
  """

  use ShubhVivahsWeb.Hologram.PlayerPageBase, route: "/gallery/:uploader/:name", section: :gallery
end
