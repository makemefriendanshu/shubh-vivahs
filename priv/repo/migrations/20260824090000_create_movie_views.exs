defmodule ShubhVivahs.Repo.Migrations.CreateMovieViews do
  use Ecto.Migration

  def change do
    create table(:movie_views) do
      add :movie_id, references(:movies, on_delete: :delete_all), null: false
      add :session_id, :string, null: false
      timestamps(updated_at: false)
    end

    create index(:movie_views, [:movie_id])
  end
end
