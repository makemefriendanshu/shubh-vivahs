defmodule ShubhVivahs.Repo.Migrations.AddLabelToFaces do
  use Ecto.Migration

  def change do
    alter table(:faces) do
      add(:label, :string)
      add(:subtitle, :string)
    end
  end
end
