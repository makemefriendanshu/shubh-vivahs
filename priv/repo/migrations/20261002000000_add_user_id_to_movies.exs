defmodule PhoenixHologram.Repo.Migrations.AddUserIdToMovies do
  use Ecto.Migration

  # Nullable: movies ingested before this column existed (including a
  # handful of seed/demo videos that were never routed through
  # VideoUpload at all) have no recorded uploader. New uploads always
  # set it — see VideoUploadController.finalize/2.
  def change do
    alter table(:movies) do
      add(:user_id, references(:users, on_delete: :nilify_all))
    end

    create index(:movies, [:user_id])
  end
end
