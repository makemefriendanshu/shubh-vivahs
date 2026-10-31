defmodule ShubhVivahs.Repo.Migrations.AddSlugToMovies do
  use Ecto.Migration

  # URL name for the player: /premiere/<uploader>/<slug> (see
  # ShubhVivahs.MovieSlug). Unique across the site; nullable so existing
  # rows get one lazily (MovieSlug.ensure/1) or from the backfill run.
  def change do
    alter table(:movies) do
      add :slug, :string
    end

    create unique_index(:movies, [:slug])
  end
end
