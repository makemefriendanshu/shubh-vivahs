defmodule ShubhVivahs.Repo.Migrations.AddMovieIdToMediaItems do
  use Ecto.Migration

  # Each library video gets a backing `movies` row so it reuses the whole
  # wedding-film pipeline (face detection, focus votes, comments, likes,
  # views, preview tiers) keyed on movie_id. See Library.ensure_movie/1.
  def change do
    alter table(:media_items) do
      add :movie_id, references(:movies, on_delete: :nilify_all)
    end

    create unique_index(:media_items, [:movie_id])
  end
end
