defmodule ShubhVivahs.Repo.Migrations.CreateFocusVotes do
  use Ecto.Migration

  def change do
    create table(:focus_votes) do
      add :movie_id, references(:movies, on_delete: :delete_all), null: false
      add :face_id, references(:faces, on_delete: :delete_all), null: false
      add :scene_start_ms, :integer, null: false
      add :scene_end_ms, :integer, null: false
      add :session_id, :string, null: false
      timestamps(updated_at: false)
    end

    create index(:focus_votes, [:movie_id])
    create index(:focus_votes, [:face_id])

    create unique_index(:focus_votes, [:movie_id, :scene_start_ms, :scene_end_ms, :session_id],
             name: :focus_votes_movie_scene_session_index
           )
  end
end
