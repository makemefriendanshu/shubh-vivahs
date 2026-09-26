defmodule PhoenixHologram.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :phone, :string
      add :avatar_url, :string
      add :wedding_date, :date
    end
  end
end
