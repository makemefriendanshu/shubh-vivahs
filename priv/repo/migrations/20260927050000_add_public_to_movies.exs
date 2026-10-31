defmodule ShubhVivahs.Repo.Migrations.AddPublicToMovies do
  use Ecto.Migration

  # New uploads default to private (see VideoUpload.assemble/5) - "private
  # by default" is about the upload flow going forward, not about hiding
  # everything already ingested. Backfilling existing rows to public
  # preserves what Home/Premiere/the nav dropdown show today; without this
  # every movie ingested before this migration would vanish from those
  # pages the moment it runs.
  def change do
    alter table(:movies) do
      add(:public, :boolean, default: false, null: false)
    end

    execute("UPDATE movies SET public = true", "")
  end
end
