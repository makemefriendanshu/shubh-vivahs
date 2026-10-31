defmodule ShubhVivahs.Photos.Photo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photos" do
    belongs_to(:album, ShubhVivahs.Photos.Album)
    # Relative to Photos.storage_dir/0. The web-sized copy and thumbnail are
    # derived from the id (Photos.web_path/1, Photos.thumb_path/1).
    field(:original_path, :string)
    field(:original_name, :string)
    # Where it was imported from, so re-running an import skips it.
    field(:source_path, :string)
    # Upright (EXIF rotation applied) size of the original.
    field(:width, :integer)
    field(:height, :integer)
    # Order within the album.
    field(:position, :integer)

    has_many(:detections, ShubhVivahs.Photos.Detection)

    timestamps(type: :utc_datetime)
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [
      :album_id,
      :original_path,
      :original_name,
      :source_path,
      :width,
      :height,
      :position
    ])
    |> validate_required([:album_id, :original_path, :original_name, :source_path, :position])
    |> unique_constraint(:source_path)
  end
end
