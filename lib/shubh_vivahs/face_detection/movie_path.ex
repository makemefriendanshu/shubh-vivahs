defmodule ShubhVivahs.FaceDetection.MoviePath do
  @moduledoc """
  Ecto type for `Movie.path`. Files inside `uploads_dir/0` are stored
  relative to it and expanded back on load, so moving or renaming the
  project folder (or deploying it elsewhere) doesn't orphan every movie's
  stored path. Paths outside the uploads folder (seed/demo videos) are
  stored as-is. Callers always see an absolute path either way.

  Note `like/2` in queries bypasses this type — patterns matched against
  `path` must be written relative to `uploads_dir/0` by hand.
  """

  use Ecto.Type

  @doc "Absolute path of the folder uploaded movie files live under."
  @spec uploads_dir() :: String.t()
  def uploads_dir, do: Path.join(:code.priv_dir(:shubh_vivahs), "face_detection/uploads")

  @impl true
  def type, do: :string

  @impl true
  def cast(path) when is_binary(path), do: {:ok, path}
  def cast(_), do: :error

  @impl true
  def load(path) when is_binary(path) do
    case Path.type(path) do
      :absolute -> {:ok, path}
      _ -> {:ok, Path.join(uploads_dir(), path)}
    end
  end

  def load(_), do: :error

  @impl true
  def dump(path) when is_binary(path) do
    {:ok, String.replace_prefix(path, uploads_dir() <> "/", "")}
  end

  def dump(_), do: :error
end
