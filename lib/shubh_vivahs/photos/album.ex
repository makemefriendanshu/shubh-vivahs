defmodule ShubhVivahs.Photos.Album do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending processing done failed)

  schema "photo_albums" do
    field(:title, :string)
    # URL name: /gallery/<uploader>/photos/<slug> — unique across albums.
    field(:slug, :string)
    # Hidden from signed-out visitors until made public, like uploads.
    field(:public, :boolean, default: false)
    field(:position, :integer)
    field(:description, :string)
    field(:event_date, :date)
    field(:location, :string)
    field(:cover_photo_id, :integer)
    # Face recognition across the album's photos.
    field(:status, :string, default: "pending")

    belongs_to(:user, ShubhVivahs.Accounts.User)
    has_many(:photos, ShubhVivahs.Photos.Photo)
    has_many(:faces, ShubhVivahs.Photos.Face)

    timestamps(type: :utc_datetime)
  end

  def changeset(album, attrs) do
    album
    |> cast(attrs, [
      :title,
      :slug,
      :public,
      :position,
      :description,
      :event_date,
      :location,
      :cover_photo_id,
      :status,
      :user_id
    ])
    |> validate_required([:title, :slug])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:slug)
  end
end
