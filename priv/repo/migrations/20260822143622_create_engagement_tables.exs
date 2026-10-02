defmodule ShubhVivahs.Repo.Migrations.CreateEngagementTables do
  use Ecto.Migration

  def change do
    create table(:movie_likes) do
      add :movie_id, references(:movies, on_delete: :delete_all), null: false
      timestamps(updated_at: false)
    end

    create index(:movie_likes, [:movie_id])

    create table(:comments) do
      add :movie_id, references(:movies, on_delete: :delete_all), null: false
      add :body, :string, null: false
      timestamps(updated_at: false)
    end

    create index(:comments, [:movie_id])

    create table(:comment_likes) do
      add :comment_id, references(:comments, on_delete: :delete_all), null: false
      timestamps(updated_at: false)
    end

    create index(:comment_likes, [:comment_id])
  end
end
