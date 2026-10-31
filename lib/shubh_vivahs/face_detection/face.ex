defmodule ShubhVivahs.FaceDetection.Face do
  use Ecto.Schema
  import Ecto.Changeset

  schema "faces" do
    field(:embedding, ShubhVivahs.FaceDetection.Embedding)
    field(:label, :string)
    field(:subtitle, :string)

    belongs_to(:movie, ShubhVivahs.FaceDetection.Movie)
    has_many(:detections, ShubhVivahs.FaceDetection.Detection)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(face, attrs) do
    face
    |> cast(attrs, [:movie_id, :embedding])
    |> validate_required([:movie_id, :embedding])
  end

  @doc "Changeset for admin-assigned identity: a heading (label) and subheading (subtitle)."
  def label_changeset(face, attrs) do
    cast(face, attrs, [:label, :subtitle])
  end
end
