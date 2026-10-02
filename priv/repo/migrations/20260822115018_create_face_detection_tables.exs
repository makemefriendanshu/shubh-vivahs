defmodule ShubhVivahs.Repo.Migrations.CreateFaceDetectionTables do
  use Ecto.Migration

  def change do
    create table(:movies) do
      add :path, :string, null: false
      add :title, :string
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create table(:faces) do
      add :movie_id, references(:movies, on_delete: :delete_all), null: false
      add :embedding, :binary, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:faces, [:movie_id])

    create table(:face_detections) do
      add :face_id, references(:faces, on_delete: :delete_all), null: false
      add :frame_time_ms, :integer, null: false
      add :bbox_x, :float, null: false
      add :bbox_y, :float, null: false
      add :bbox_w, :float, null: false
      add :bbox_h, :float, null: false
      add :confidence, :float, null: false
    end

    create index(:face_detections, [:face_id])
  end
end
