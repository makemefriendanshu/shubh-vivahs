defmodule ShubhVivahs.Photos.Vote do
  use Ecto.Schema
  import Ecto.Changeset

  # "Who's in focus?" vote: one viewer session picking a face in a photo.
  schema "photo_votes" do
    belongs_to(:photo, ShubhVivahs.Photos.Photo)
    belongs_to(:face, ShubhVivahs.Photos.Face)
    field(:session_id, :string)
    timestamps(type: :utc_datetime)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:photo_id, :face_id, :session_id])
    |> validate_required([:photo_id, :face_id, :session_id])
    |> unique_constraint([:photo_id, :face_id, :session_id])
  end
end
