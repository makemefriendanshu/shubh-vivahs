defmodule ShubhVivahsWeb.MovieAccess do
  @moduledoc """
  Who may fetch a movie's files over plain HTTP (video streams, downloads,
  thumbnails): anyone for a public movie, signed-in users only for a
  private one — the same rule PlayerPage applies to the page itself.
  Library movies (see `ShubhVivahs.Library`) are always private. Photo
  albums follow the same rule.
  """

  alias ShubhVivahs.FaceDetection.Movie

  @spec viewable?(Plug.Conn.t(), Movie.t() | ShubhVivahs.Photos.Album.t()) :: boolean
  def viewable?(_conn, %{public: true}), do: true
  def viewable?(conn, %{public: _}), do: not is_nil(Hologram.Runtime.Session.get_user_id(conn))
end
