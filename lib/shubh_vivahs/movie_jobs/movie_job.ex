defmodule ShubhVivahs.MovieJobs.MovieJob do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(recognition versions)
  @statuses ~w(running done failed)

  schema "movie_jobs" do
    belongs_to(:movie, ShubhVivahs.FaceDetection.Movie)
    # "recognition" (face detection) or "versions" (quality proxies + download parts).
    field(:kind, :string)
    field(:status, :string)
    # Human-readable step, e.g. "Detecting faces" — nil before the first report.
    field(:stage, :string)
    # 0.0..1.0 across the whole job, or nil while a step can't measure itself.
    field(:progress, :float)
    # Failure reason, shown to admins.
    field(:message, :string)
    field(:started_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [:movie_id, :kind, :status, :stage, :progress, :message, :started_at])
    |> validate_required([:movie_id, :kind, :status])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
  end
end
