defmodule ShubhVivahs.Repo.Migrations.CreatePageVisits do
  use Ecto.Migration

  def change do
    create table(:page_visits) do
      add(:path, :string, null: false)
      add(:ip, :string, null: false)
      add(:referrer, :string)
      add(:method, :string, null: false)
      add(:status, :integer)
      add(:duration_ms, :integer)

      timestamps(updated_at: false)
    end

    create(index(:page_visits, [:inserted_at]))
    create(index(:page_visits, [:path]))
    create(index(:page_visits, [:ip]))
  end
end
