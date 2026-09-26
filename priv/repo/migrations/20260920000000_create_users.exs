defmodule PhoenixHologram.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :is_superuser, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:users, [:email])
  end
end
