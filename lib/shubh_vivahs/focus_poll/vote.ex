defmodule ShubhVivahs.FocusPoll.Vote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "focus_votes" do
    field :movie_id, :id
    field :face_id, :id
    field :scene_start_ms, :integer
    field :scene_end_ms, :integer
    field :session_id, :string
    timestamps(updated_at: false)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:movie_id, :face_id, :scene_start_ms, :scene_end_ms, :session_id])
    |> validate_required([:movie_id, :face_id, :scene_start_ms, :scene_end_ms, :session_id])
  end
end
