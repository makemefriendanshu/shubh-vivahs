defmodule ShubhVivahs.Repo.Migrations.AddAuthorNameToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :author_name, :string
    end
  end
end
