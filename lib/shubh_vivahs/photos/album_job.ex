defmodule ShubhVivahs.Photos.AlbumJob do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(recognition)
  @statuses ~w(running done failed)

  schema "photo_album_jobs" do
    belongs_to(:album, ShubhVivahs.Photos.Album)
    # "recognition" (face detection across the album's photos).
    field(:kind, :string)
    field(:status, :string)
    # Human-readable step, e.g. "Detecting faces" — nil before the first report.
    field(:stage, :string)
    # 0.0..1.0 across the whole job.
    field(:progress, :float)
    # Failure reason, shown to admins.
    field(:message, :string)
    field(:started_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [:album_id, :kind, :status, :stage, :progress, :message, :started_at])
    |> validate_required([:album_id, :kind, :status])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
  end
end
