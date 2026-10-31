defmodule ShubhVivahs.Photos.Face do
  use Ecto.Schema
  import Ecto.Changeset

  # One recognised person within an album (faces are grouped per album).
  schema "photo_faces" do
    belongs_to(:album, ShubhVivahs.Photos.Album)
    field(:label, :string)
    field(:subtitle, :string)
    field(:embedding, ShubhVivahs.FaceDetection.Embedding)
    has_many(:detections, ShubhVivahs.Photos.Detection)
    timestamps(type: :utc_datetime)
  end

  def changeset(face, attrs) do
    face
    |> cast(attrs, [:album_id, :label, :subtitle, :embedding])
    |> validate_required([:album_id, :embedding])
  end

  def label_changeset(face, attrs), do: cast(face, attrs, [:label, :subtitle])
end
