defmodule ShubhVivahs.FaceDetection.MoviePath do
  @moduledoc """
  Ecto type for `Movie.path`. Files inside `uploads_dir/0` are stored
  relative to it and expanded back on load, so moving or renaming the
  project folder (or deploying it elsewhere) doesn't orphan every movie's
  stored path. Paths outside the uploads folder (seed/demo videos) are
  stored as-is. Media library files (backing movies for `ShubhVivahs.Library`
  videos) are stored relative to `Library.storage_dir/0` behind a
  `@library/` marker for the same reason. Callers always see an
  absolute path either way.

  Note `like/2` in queries bypasses this type — patterns matched against
  `path` must be written relative to `uploads_dir/0` by hand.
  """

  use Ecto.Type

  @library_prefix "@library/"

  @doc "Absolute path of the folder uploaded movie files live under."
  @spec uploads_dir() :: String.t()
  def uploads_dir, do: Path.join(:code.priv_dir(:shubh_vivahs), "face_detection/uploads")

  @impl true
  def type, do: :string

  @impl true
  def cast(path) when is_binary(path), do: {:ok, path}
  def cast(_), do: :error

  @impl true
  def load(@library_prefix <> relative),
    do: {:ok, Path.join(ShubhVivahs.Library.storage_dir(), relative)}

  def load(path) when is_binary(path) do
    case Path.type(path) do
      :absolute -> {:ok, path}
      _ -> {:ok, Path.join(uploads_dir(), path)}
    end
  end

  def load(_), do: :error

  @impl true
  def dump(path) when is_binary(path) do
    library_dir = ShubhVivahs.Library.storage_dir() <> "/"

    if String.starts_with?(path, library_dir) do
      {:ok, @library_prefix <> String.replace_prefix(path, library_dir, "")}
    else
      {:ok, String.replace_prefix(path, uploads_dir() <> "/", "")}
    end
  end

  def dump(_), do: :error
end
