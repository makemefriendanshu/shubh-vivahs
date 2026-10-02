defmodule ShubhVivahs.Engagement.MovieView do
  use Ecto.Schema
  import Ecto.Changeset

  schema "movie_views" do
    field :movie_id, :id
    field :session_id, :string
    timestamps(updated_at: false)
  end

  def changeset(view, attrs) do
    view
    |> cast(attrs, [:movie_id, :session_id])
    |> validate_required([:movie_id, :session_id])
  end
end
