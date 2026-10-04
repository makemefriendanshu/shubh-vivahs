defmodule ShubhVivahs.Repo.Migrations.AddSessionIdToLikes do
  use Ecto.Migration

  def change do
    alter table(:movie_likes) do
      add :session_id, :string, null: false
    end

    create unique_index(:movie_likes, [:movie_id, :session_id])

    alter table(:comment_likes) do
      add :session_id, :string, null: false
    end

    create unique_index(:comment_likes, [:comment_id, :session_id])
  end
end
