defmodule ShubhVivahs.FaceDetection.Embedding do
  @moduledoc """
  Ecto type storing a face embedding (a list of floats) as packed
  native-endian 32-bit floats, so `faces.embedding` round-trips as a
  plain list of floats everywhere else in the app.
  """

  use Ecto.Type

  def type, do: :binary

  def cast(value) when is_list(value), do: {:ok, value}
  def cast(_), do: :error

  def dump(value) when is_list(value) do
    {:ok, for(f <- value, into: <<>>, do: <<f::float-32-native>>)}
  end

  def dump(_), do: :error

  def load(binary) when is_binary(binary) do
    {:ok, for(<<f::float-32-native <- binary>>, do: f)}
  end
end
