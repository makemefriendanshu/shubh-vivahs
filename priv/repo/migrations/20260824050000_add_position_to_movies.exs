defmodule ShubhVivahs.Repo.Migrations.AddPositionToMovies do
  use Ecto.Migration

  def change do
    alter table(:movies) do
      add :position, :integer
    end
  end
end
