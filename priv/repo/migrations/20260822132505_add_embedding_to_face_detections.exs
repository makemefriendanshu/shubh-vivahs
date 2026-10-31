defmodule ShubhVivahs.Repo.Migrations.AddEmbeddingToFaceDetections do
  use Ecto.Migration

  def change do
    alter table(:face_detections) do
      add(:embedding, :binary)
    end
  end
end
