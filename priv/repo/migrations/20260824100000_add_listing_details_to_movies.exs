defmodule ShubhVivahs.Repo.Migrations.AddListingDetailsToMovies do
  use Ecto.Migration

  def change do
    alter table(:movies) do
      add :description, :text
      add :event_date, :date
      add :location, :string
    end
  end
end
