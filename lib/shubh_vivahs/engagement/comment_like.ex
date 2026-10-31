defmodule ShubhVivahs.Engagement.CommentLike do
  use Ecto.Schema
  import Ecto.Changeset

  schema "comment_likes" do
    field :comment_id, :id
    field :session_id, :string
    timestamps(updated_at: false)
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:comment_id, :session_id])
    |> validate_required([:comment_id, :session_id])
  end
end
