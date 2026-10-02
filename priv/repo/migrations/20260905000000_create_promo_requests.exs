defmodule ShubhVivahs.Repo.Migrations.CreatePromoRequests do
  use Ecto.Migration

  def change do
    create table(:promo_requests) do
      add :description, :string, null: false
      add :amount, :integer, null: false
      add :code, :string, null: false
      add :status, :string, null: false, default: "pending"

      timestamps()
    end

    create index(:promo_requests, [:status])
  end
end
