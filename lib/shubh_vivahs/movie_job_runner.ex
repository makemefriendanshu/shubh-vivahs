defmodule ShubhVivahs.MovieJobRunner do
  @moduledoc """
  Runs one long per-movie job in the background, on demand — the buttons
  on AdminMoviePage:

    * `"recognition"` — face detection. Library movies (see
      `ShubhVivahs.Library`) go through `Library.detect_faces/1` (2s
      sampling), wedding films through `FaceDetection.ingest_video/2` (1s).
      Re-running replaces the movie's faces, which cascades to their names
      and focus votes — the page asks first.
    * `"versions"` — 720p/360p proxies and download parts
      (`ShubhVivahs.QualityVersions`).

  Only one job at a time inside the web server: both are CPU-heavy and the
  server is also what serves the site. A job already running for the movie
  (started here, by an upload, or by a `mix` task) is refused rather than
  run twice — unless it's stalled (see `MovieJobs.stalled?/1`), i.e. its
  process died without saying so.

  Progress is tracked in `ShubhVivahs.MovieJobs`; when a job ends this
  broadcasts `:movies_updated` so open admin pages refresh.
  """

  require Logger
  import Ecto.Query

  alias ShubhVivahs.FaceDetection
  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.Library
  alias ShubhVivahs.MovieJobs
  alias ShubhVivahs.QualityVersions
  alias ShubhVivahs.Repo

  @kinds ~w(recognition versions)

  @doc """
  Starts `kind` for `movie_id`. Returns `:ok`, or `{:error, reason}` with
  `reason` one of `:not_found`, `:already_running` (this job, this movie),
  or `:busy` (the server is already running a job for some movie).
  """
  @spec start(integer, String.t()) :: :ok | {:error, :not_found | :already_running | :busy}
  def start(movie_id, kind) when kind in @kinds do
    cond do
      running?() or ShubhVivahs.Photos.RecognitionRunner.running?() ->
        {:error, :busy}

      Repo.get(Movie, movie_id) == nil ->
        {:error, :not_found}

      claim(movie_id, kind) == :taken ->
        {:error, :already_running}

      true ->
        {:ok, _pid} =
          Task.Supervisor.start_child(ShubhVivahs.TaskSupervisor, fn -> run(movie_id, kind) end)

        :ok
    end
  end

  @doc "Whether the web server is running a job right now (for any movie)."
  def running?, do: Process.whereis(__MODULE__) != nil

  # Recognition is claimed through the movie's own status (what uploads and
  # `mix library.detect_faces` check too), atomically so two clicks can't
  # both start it. A stalled run's "processing" is taken over.
  defp claim(movie_id, "recognition") do
    stalled? = MovieJobs.stalled?(MovieJobs.get(movie_id, "recognition"))

    query =
      if stalled?,
        do: from(m in Movie, where: m.id == ^movie_id),
        else: from(m in Movie, where: m.id == ^movie_id and m.status != "processing")

    case Repo.update_all(query,
           set: [status: "processing", updated_at: DateTime.utc_now(:second)]
         ) do
      {1, _} -> :ok
      {0, _} -> :taken
    end
  end

  defp claim(movie_id, "versions") do
    job = MovieJobs.get(movie_id, "versions")

    if job && job.status == "running" && !MovieJobs.stalled?(job) do
      :taken
    else
      # Shows as running straight away, before the task gets going.
      MovieJobs.start(movie_id, "versions")
    end
  end

  defp run(movie_id, kind) do
    Process.register(self(), __MODULE__)
    movie = Repo.get!(Movie, movie_id)

    result =
      try do
        do_run(movie, kind)
      rescue
        exception -> {:error, Exception.message(exception)}
      end

    with {:error, reason} <- result do
      Logger.error("#{kind} failed for movie #{movie_id}: #{inspect(reason)}")
      MovieJobs.fail(movie_id, kind, reason)

      # ingest_video marks most recognition failures itself; this covers a crash.
      if kind == "recognition" do
        Repo.update_all(from(m in Movie, where: m.id == ^movie_id), set: [status: "failed"])
      end
    end

    Hologram.Realtime.broadcast_action(:movies_changed, :movies_updated)
  end

  defp do_run(movie, "recognition") do
    case Library.get_by_movie_id(movie.id) do
      nil -> FaceDetection.ingest_video(movie.path, title: movie.title)
      item -> Library.detect_faces(item)
    end
  end

  defp do_run(movie, "versions"), do: QualityVersions.generate(movie)
end
