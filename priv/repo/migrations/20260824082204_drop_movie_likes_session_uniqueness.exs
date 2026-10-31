defmodule ShubhVivahs.Repo.Migrations.DropMovieLikesSessionUniqueness do
  use Ecto.Migration

  # Movie likes are no longer "one per session" - every click on the Like
  # button adds a fresh like, so a session can have more than one row here.
  def change do
    drop unique_index(:movie_likes, [:movie_id, :session_id])
  end
end
