defmodule ShubhVivahs.Repo.Migrations.CreateMediaItems do
  use Ecto.Migration

  # General media library (series, movies, songs) — kept separate from the
  # wedding `movies` table so these never go through face detection,
  # engagement, or the public showcase. See ShubhVivahs.Library.
  def change do
    create table(:media_items) do
      add :kind, :string, null: false
      add :title, :string, null: false
      # Series name for episodes, artist for songs, nil for movies.
      add :collection, :string
      add :season, :integer
      add :episode, :integer
      # Relative to Library.storage_dir/0; nil until the import finishes.
      add :path, :string
      add :source_path, :string, null: false
      add :status, :string, null: false, default: "processing"
      add :has_subtitles, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:media_items, [:source_path])
    create index(:media_items, [:kind])
  end
end
