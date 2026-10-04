defmodule ShubhVivahs.Repo.Migrations.AddSubcommentsToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :parent_id, references(:comments, on_delete: :delete_all)
      add :session_id, :string, null: false
    end

    create index(:comments, [:parent_id])
  end
end
