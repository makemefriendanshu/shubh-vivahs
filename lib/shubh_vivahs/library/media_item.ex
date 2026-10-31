defmodule ShubhVivahs.Library.MediaItem do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(series movie song)
  @statuses ~w(processing ready failed)

  schema "media_items" do
    # "series" (one row per episode), "movie", or "song".
    field(:kind, :string)
    field(:title, :string)
    # Series name for episodes, artist for songs, nil for movies.
    field(:collection, :string)
    field(:season, :integer)
    field(:episode, :integer)
    # Browser-playable copy, relative to `Library.storage_dir/0` — nil
    # until the import finishes (see `Library.Importer`).
    field(:path, :string)
    # The file this was imported from, so re-running an import skips it.
    field(:source_path, :string)
    field(:status, :string, default: "processing")
    # Whether a WebVTT file sits next to `path` (same name, .vtt).
    field(:has_subtitles, :boolean, default: false)
    # Comma-separated ISO 639-2 codes ("eng,hin"): the first is the main
    # file's audio, each other one has its own copy next to it — see
    # Library.audio_versions/1. nil for single-language items.
    field(:audio_languages, :string)

    # Backing wedding-pipeline movie (faces, comments, likes, views) for
    # videos — nil for songs and for anything not linked yet. See
    # `Library.ensure_movie/1`.
    belongs_to(:movie, ShubhVivahs.FaceDetection.Movie)

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :kind,
      :title,
      :collection,
      :season,
      :episode,
      :path,
      :source_path,
      :status,
      :has_subtitles,
      :audio_languages,
      :movie_id
    ])
    |> validate_required([:kind, :title, :source_path])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:source_path)
    |> unique_constraint(:movie_id)
  end
end
