defmodule ShubhVivahs.Repo.Migrations.CreateMovieJobs do
  use Ecto.Migration

  # Progress of long-running per-movie jobs (face recognition, quality
  # versions), written by whichever OS process runs them — the web server
  # or a `mix` task — and polled by AdminMoviePage. See ShubhVivahs.MovieJobs.
  def change do
    create table(:movie_jobs) do
      add :movie_id, references(:movies, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :status, :string, null: false
      add :stage, :string
      add :progress, :float
      add :message, :text
      add :started_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:movie_jobs, [:movie_id, :kind])
  end
end
