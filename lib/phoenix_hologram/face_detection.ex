defmodule PhoenixHologram.FaceDetection do
  @moduledoc """
  Ingests a video, detects faces per sampled frame, clusters them into
  unique identities, and persists the result: one `Movie`, one `Face`
  row per unique identity, and one `Detection` row per raw sighting.
  Detections carry `:frame_time_ms` and `:face_id`, so
  `PhoenixHologram.FaceDetection.SceneIndex` can later derive each
  face's own timestamp ranges, or the movie's real scene timeline
  (segments where the same set of faces is on screen together).
  """

  import Ecto.Query

  alias PhoenixHologram.FaceDetection.{
    Clustering,
    Detection,
    Face,
    FrameExtractor,
    Movie,
    ModelServer
  }

  alias PhoenixHologram.FaceThumbnail
  alias PhoenixHologram.MovieThumbnail
  alias PhoenixHologram.Repo
  alias PhoenixHologram.VideoPreview

  @doc """
  Ingests `video_path`, returning `{:ok, movie}` with its `:faces` (each
  preloaded with `:detections`) or `{:error, reason}`.

  Options:
    * `:title` - stored on the movie record
    * `:fps` - frame sampling rate, default 1
    * `:cluster_threshold` - cosine-similarity threshold, see `Clustering`
  """
  def ingest_video(video_path, opts \\ []) do
    normalized_path = Path.expand(video_path)

    with {:ok, movie} <- create_movie(normalized_path, opts) do
      case do_ingest(movie, normalized_path, opts) do
        {:ok, result} ->
          {:ok, result}

        {:error, reason} ->
          movie |> Movie.changeset(%{status: "failed"}) |> Repo.update()
          {:error, reason}
      end
    end
  end

  defp do_ingest(movie, video_path, opts) do
    with {:ok, frames} <- FrameExtractor.extract_frames(video_path, opts) do
      try do
        with {:ok, detections} <- detect_all(frames) do
          persist_clusters(movie, detections, opts)
        end
      after
        cleanup_frames(frames)
      end
    end
  end

  @doc """
  Assigns an admin-chosen identity to a face: a heading (`:label`) and
  an optional subheading (`:subtitle`). Returns `{:ok, face}` or
  `{:error, changeset}`.
  """
  def label_face(face_id, attrs) do
    Face
    |> Repo.get!(face_id)
    |> Face.label_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Renames a movie — both its title and, when the file lives under
  `VideoUpload`'s managed storage, its on-disk filename (see
  `VideoUpload.rename_for_title/2`). Returns `{:ok, movie}` or
  `{:error, changeset}`.
  """
  def rename_movie(movie_id, title) do
    movie = Repo.get!(Movie, movie_id)
    new_path = PhoenixHologram.VideoUpload.rename_for_title(movie, title)

    movie
    |> Movie.changeset(%{title: title, path: new_path})
    |> Repo.update()
  end

  @doc """
  Updates a movie's listing details (blurb, event date, location) shown on
  its card in Premiere Hall and admin. Returns `{:ok, movie}` or
  `{:error, changeset}`.
  """
  def update_movie_details(movie_id, attrs) do
    Movie
    |> Repo.get!(movie_id)
    |> Movie.details_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Every movie in display order: by `:position` (nulls last, so a movie
  nobody has explicitly ordered still shows up instead of disappearing),
  then `:id` as a stable tiebreaker. The single source of truth for movie
  order across every listing (Premiere Hall, admin, the nav dropdowns) —
  order here, not insertion/ingest order, which is an implementation
  detail unrelated to the actual event sequence. Includes private movies —
  this is what DashboardPage/UploadPage/AdminMoviesPage show, since any
  authenticated user manages the whole shared catalog regardless of
  visibility (see `Movie`'s `:public` field doc). Public-facing pages use
  `list_public_movies_ordered/0` instead.
  """
  def list_movies_ordered do
    Repo.all(
      from m in Movie,
        order_by: [
          asc: fragment("CASE WHEN ? IS NULL THEN 1 ELSE 0 END", m.position),
          asc: m.position,
          asc: m.id
        ]
    )
  end

  @doc """
  Same ordering as `list_movies_ordered/0`, filtered to movies marked
  `public: true` — what Home, Premiere Hall, and the nav dropdown show to
  anonymous visitors. A freshly uploaded movie defaults to private (see
  `PhoenixHologram.VideoUpload`) so it doesn't show up here until someone
  flips it public from Dashboard/UploadPage.
  """
  def list_public_movies_ordered do
    Repo.all(
      from m in Movie,
        where: m.public == true,
        order_by: [
          asc: fragment("CASE WHEN ? IS NULL THEN 1 ELSE 0 END", m.position),
          asc: m.position,
          asc: m.id
        ]
    )
  end

  # The Home page's showcase is Anshuman's own catalog specifically, not
  # "whoever happens to be a superuser" — a newly promoted superuser's
  # uploads must not start appearing there, so this is pinned to his
  # user id rather than derived from the `:is_superuser` flag.
  @home_showcase_user_id 4

  @doc """
  Same as `list_public_movies_ordered/0`, further restricted to movies
  owned by the Home page's showcase account (`@home_showcase_user_id`).
  Anonymous visitors only ever see that one account's public videos, not
  every public movie in the shared catalog, and not any other
  superuser's.
  """
  def list_superuser_public_movies_ordered do
    Repo.all(
      from m in Movie,
        where: m.public == true and m.user_id == ^@home_showcase_user_id,
        order_by: [
          asc: fragment("CASE WHEN ? IS NULL THEN 1 ELSE 0 END", m.position),
          asc: m.position,
          asc: m.id
        ]
    )
  end

  @doc """
  Sets whether `movie_id` shows on public-facing pages. Returns `{:ok,
  movie}` or `{:error, changeset}`.
  """
  def set_movie_visibility(movie_id, public?) do
    Movie
    |> Repo.get!(movie_id)
    |> Movie.visibility_changeset(%{public: public?})
    |> Repo.update()
  end

  @doc """
  Permanently deletes a movie: its DB row (`Face`/`Detection` rows cascade
  at the database level, per the `movies`/`faces`/`face_detections`
  migration's `on_delete: :delete_all` foreign keys), every file generated
  for it (thumbnails, preview proxies, download segments, metadata cache),
  and the original uploaded source file. Returns `{:ok, movie}` or
  `{:error, :not_found}`. Missing files are not an error — deleting
  something already gone is the desired end state either way.
  """
  @spec delete_movie(term) :: {:ok, Movie.t()} | {:error, :not_found}
  def delete_movie(movie_id) do
    case Repo.get(Movie, movie_id) do
      nil ->
        {:error, :not_found}

      movie ->
        movie = Repo.preload(movie, :faces)
        Enum.each(movie.faces, &File.rm(FaceThumbnail.thumbnail_path(&1)))
        File.rm(MovieThumbnail.thumbnail_path(movie))
        File.rm(VideoPreview.preview_path(movie))
        File.rm(VideoPreview.minimal_path(movie))
        File.rm_rf(segments_dir(movie))
        Enum.each(metadata_paths(movie), &File.rm/1)
        File.rm(movie.path)
        Repo.delete(movie)
    end
  end

  defp segments_dir(movie) do
    Path.join([:code.priv_dir(:phoenix_hologram), "face_detection/movie_segments", "#{movie.id}"])
  end

  defp metadata_paths(movie) do
    dir = Path.join(:code.priv_dir(:phoenix_hologram), "face_detection/movie_metadata")

    Enum.map(
      ["#{movie.id}.json", "#{movie.id}_preview.json", "#{movie.id}_minimal.json"],
      &Path.join(dir, &1)
    )
  end

  defp cleanup_frames([]), do: :ok

  defp cleanup_frames([%{path: path} | _]) do
    path |> Path.dirname() |> File.rm_rf!()
  end

  # Re-ingesting a path that's already a movie (whether from a previous
  # ingest or a seeded row) reuses that row and clears its old faces
  # instead of creating a duplicate movie.
  defp create_movie(video_path, opts) do
    case Repo.get_by(Movie, path: video_path) do
      nil ->
        %Movie{}
        |> Movie.changeset(%{
          path: video_path,
          title: Keyword.get(opts, :title),
          status: "processing"
        })
        |> Repo.insert()

      movie ->
        Repo.delete_all(from f in Face, where: f.movie_id == ^movie.id)

        attrs =
          case Keyword.get(opts, :title) do
            nil -> %{status: "processing"}
            title -> %{status: "processing", title: title}
          end

        movie |> Movie.changeset(attrs) |> Repo.update()
    end
  end

  defp detect_all(frames) do
    Enum.reduce_while(frames, {:ok, []}, fn frame, {:ok, acc} ->
      case ModelServer.detect_faces(frame.path) do
        {:ok, faces} ->
          detections = Enum.map(faces, &Map.put(&1, :timestamp_ms, frame.timestamp_ms))
          {:cont, {:ok, detections ++ acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_clusters(movie, detections, opts) do
    clusters = Clustering.cluster(detections, opts)

    Repo.transaction(fn ->
      for cluster <- clusters do
        {:ok, face} =
          %Face{}
          |> Face.changeset(%{movie_id: movie.id, embedding: cluster.centroid})
          |> Repo.insert()

        for detection <- cluster.members do
          {x, y, w, h} = detection.bbox

          {:ok, _} =
            %Detection{}
            |> Detection.changeset(%{
              face_id: face.id,
              frame_time_ms: detection.timestamp_ms,
              bbox_x: x,
              bbox_y: y,
              bbox_w: w,
              bbox_h: h,
              confidence: detection.confidence,
              embedding: detection.embedding
            })
            |> Repo.insert()
        end
      end

      movie
      |> Movie.changeset(%{status: "done"})
      |> Repo.update!()
      |> Repo.preload(faces: :detections)
    end)
  end
end
