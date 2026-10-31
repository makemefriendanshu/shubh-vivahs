defmodule ShubhVivahs.Engagement.MovieLike do
  use Ecto.Schema
  import Ecto.Changeset

  schema "movie_likes" do
    field :movie_id, :id
    field :session_id, :string
    timestamps(updated_at: false)
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:movie_id, :session_id])
    |> validate_required([:movie_id, :session_id])
  end
end
