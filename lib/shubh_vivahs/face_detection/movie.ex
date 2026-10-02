defmodule ShubhVivahs.FaceDetection.Movie do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending processing done failed)

  schema "movies" do
    field(:path, :string)
    field(:title, :string)
    field(:status, :string, default: "pending")
    # Display order across every movie listing (Premiere Hall, admin, nav
    # dropdowns) — nil for movies ingested before this field existed, or
    # any movie nobody has explicitly ordered, sorts after every movie
    # that has a position (see FaceDetection.list_movies_ordered/0).
    field(:position, :integer)
    # Admin-authored blurb, event date, and location shown on movie cards
    # in place of raw file metadata (Premiere Hall, admin) — all nil until
    # an admin fills them in, in which case the card just omits them.
    field(:description, :string)
    field(:event_date, :date)
    field(:location, :string)
    # Whether this movie shows on public-facing pages (Home, Premiere Hall,
    # the nav dropdown) - defaults false so a freshly uploaded video isn't
    # shown off to anonymous visitors before its owner is ready. Any
    # authenticated user still sees it in Dashboard/UploadPage/AdminMoviesPage
    # regardless, same as every other movie in this app's one shared
    # catalog (see DashboardPage's moduledoc).
    field(:public, :boolean, default: false)

    # Who uploaded this — nil for movies ingested before this column
    # existed (including seed/demo videos that were never routed through
    # VideoUpload). Doesn't change this app's one-shared-catalog model
    # (see DashboardPage's moduledoc — every signed-in user still sees
    # and manages every movie regardless of uploader); it only drives
    # which on-disk folder a fresh upload's file lands in.
    belongs_to(:user, ShubhVivahs.Accounts.User)

    has_many(:faces, ShubhVivahs.FaceDetection.Face)

    timestamps(type: :utc_datetime)
  end

  def changeset(movie, attrs) do
    movie
    |> cast(attrs, [:path, :title, :status, :position, :public, :user_id])
    |> validate_required([:path])
    |> validate_inclusion(:status, @statuses)
  end

  @doc "Changeset for admin-authored listing details: blurb, event date, and location."
  def details_changeset(movie, attrs) do
    cast(movie, attrs, [:description, :event_date, :location])
  end

  @doc "Changeset for toggling whether a movie is shown on public-facing pages."
  def visibility_changeset(movie, attrs) do
    cast(movie, attrs, [:public])
  end
end
