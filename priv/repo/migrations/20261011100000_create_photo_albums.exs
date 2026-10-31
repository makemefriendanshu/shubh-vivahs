defmodule ShubhVivahs.Repo.Migrations.CreatePhotoAlbums do
  use Ecto.Migration

  # Photo albums in the wedding gallery (see ShubhVivahs.Photos): albums,
  # their photos, faces recognised per album, each face sighting, focus
  # votes per photo, and job progress for the admin page.
  def change do
    create table(:photo_albums) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :public, :boolean, null: false, default: false
      add :position, :integer
      add :description, :text
      add :event_date, :date
      add :location, :string
      add :cover_photo_id, :integer
      # Face recognition: pending / processing / done / failed.
      add :status, :string, null: false, default: "pending"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:photo_albums, [:slug])

    create table(:photos) do
      add :album_id, references(:photo_albums, on_delete: :delete_all), null: false
      # Relative to Photos.storage_dir/0.
      add :original_path, :string, null: false
      add :original_name, :string, null: false
      add :source_path, :string, null: false
      add :width, :integer
      add :height, :integer
      add :position, :integer, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:photos, [:album_id, :position])
    create unique_index(:photos, [:source_path])

    create table(:photo_faces) do
      add :album_id, references(:photo_albums, on_delete: :delete_all), null: false
      add :label, :string
      add :subtitle, :string
      add :embedding, :binary, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:photo_faces, [:album_id])

    create table(:photo_detections) do
      add :photo_id, references(:photos, on_delete: :delete_all), null: false
      add :face_id, references(:photo_faces, on_delete: :delete_all), null: false
      # Bounding box in the web-sized copy's pixels.
      add :bbox_x, :float
      add :bbox_y, :float
      add :bbox_w, :float
      add :bbox_h, :float
      add :confidence, :float
      add :embedding, :binary
      timestamps(type: :utc_datetime)
    end

    create index(:photo_detections, [:photo_id])
    create index(:photo_detections, [:face_id])

    create table(:photo_votes) do
      add :photo_id, references(:photos, on_delete: :delete_all), null: false
      add :face_id, references(:photo_faces, on_delete: :delete_all), null: false
      add :session_id, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:photo_votes, [:photo_id, :face_id, :session_id])
    create index(:photo_votes, [:face_id])

    create table(:photo_album_jobs) do
      add :album_id, references(:photo_albums, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :status, :string, null: false
      add :stage, :string
      add :progress, :float
      add :message, :text
      add :started_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:photo_album_jobs, [:album_id, :kind])
  end
end
