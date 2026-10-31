defmodule ShubhVivahs.Repo.Migrations.CreateLeads do
  use Ecto.Migration

  def change do
    create table(:leads) do
      add :name, :string, null: false
      add :wedding_date, :date
      add :email, :string, null: false

      timestamps(updated_at: false)
    end
  end
end
