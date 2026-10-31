defmodule ShubhVivahs.MovieJobs do
  @moduledoc """
  Progress tracking for long-running per-movie jobs — face recognition
  and quality versions — so AdminMoviePage can show a progress bar.

  Jobs run in whichever OS process started them (the web server via
  `ShubhVivahs.MovieJobRunner`, or a `mix` task), so progress goes through
  the database rather than PubSub; the page polls it. One row per movie
  and kind, overwritten by each new run.

  A job's process can die without saying so (an OOM kill, a stopped
  service), leaving it "running" forever. Running jobs report at least
  every few seconds, so one silent for `@stall_after_s` is treated as
  stalled (`stalled?/1`) and may be started again.
  """

  import Ecto.Query

  alias ShubhVivahs.MovieJobs.MovieJob
  alias ShubhVivahs.Repo

  @stall_after_s 10 * 60

  @doc "The latest job of `kind` for `movie_id`, or nil if it was never run."
  def get(movie_id, kind), do: Repo.get_by(MovieJob, movie_id: movie_id, kind: kind)

  @doc "Marks a job as started (replacing any previous run's row)."
  def start(movie_id, kind) do
    now = DateTime.utc_now(:second)

    upsert(movie_id, kind, %{
      status: "running",
      stage: nil,
      progress: 0.0,
      message: nil,
      started_at: now
    })
  end

  @doc """
  Returns a `fn stage, progress -> :ok end` for a running job that writes
  only when the stage changes or progress has moved at least 1% since the
  last write (and always at most every ~2s otherwise) — callers can report
  per frame without hammering the database.
  """
  def reporter(movie_id, kind) do
    key = {__MODULE__, movie_id, kind}

    fn stage, progress ->
      now = System.monotonic_time(:millisecond)
      progress = progress && progress |> max(0.0) |> min(1.0)

      case Process.get(key) do
        {^stage, last, at}
        when is_number(progress) and is_number(last) and
               progress - last < 0.01 and now - at < 2_000 ->
          :ok

        _ ->
          Process.put(key, {stage, progress, now})
          write(movie_id, kind, %{stage: stage, progress: progress})
          :ok
      end
    end
  end

  @doc "Marks a job finished successfully."
  def finish(movie_id, kind), do: write(movie_id, kind, %{status: "done", progress: 1.0})

  @doc "Marks a job failed with a short reason."
  def fail(movie_id, kind, reason) do
    message = if is_binary(reason), do: reason, else: inspect(reason)
    write(movie_id, kind, %{status: "failed", message: String.slice(message, 0, 500)})
  end

  @doc "True for a job still marked running that hasn't reported for a while."
  def stalled?(%MovieJob{status: "running", updated_at: updated_at}) do
    DateTime.diff(DateTime.utc_now(), updated_at) > @stall_after_s
  end

  def stalled?(_job), do: false

  @doc """
  Seconds left, extrapolated from progress so far — nil until there's
  enough progress to say (under 2%, the first estimates swing wildly).
  """
  def seconds_left(%MovieJob{
        status: "running",
        progress: progress,
        started_at: %DateTime{} = started
      })
      when is_number(progress) and progress >= 0.02 do
    elapsed = DateTime.diff(DateTime.utc_now(), started)
    round(elapsed * (1 - progress) / progress)
  end

  def seconds_left(_job), do: nil

  defp write(movie_id, kind, attrs) do
    {_count, _} =
      Repo.update_all(
        from(j in MovieJob, where: j.movie_id == ^movie_id and j.kind == ^kind),
        set: Keyword.new(Map.put(attrs, :updated_at, DateTime.utc_now(:second)))
      )

    :ok
  end

  defp upsert(movie_id, kind, attrs) do
    %MovieJob{}
    |> MovieJob.changeset(Map.merge(attrs, %{movie_id: movie_id, kind: kind}))
    |> Repo.insert!(
      on_conflict: {:replace, [:status, :stage, :progress, :message, :started_at, :updated_at]},
      conflict_target: [:movie_id, :kind]
    )

    :ok
  end
end
