defmodule ShubhVivahs.Photos.AlbumJobs do
  @moduledoc """
  Progress of long per-album jobs (face recognition), the photo-album
  counterpart of `ShubhVivahs.MovieJobs`: one row per album and kind,
  written by whichever OS process runs the job (the web server or a `mix`
  task) and polled by the admin page.
  """

  import Ecto.Query

  alias ShubhVivahs.Photos.AlbumJob
  alias ShubhVivahs.Repo

  @stall_after_s 10 * 60

  def get(album_id, kind), do: Repo.get_by(AlbumJob, album_id: album_id, kind: kind)

  @doc "Marks a job as started (replacing any previous run's row)."
  def start(album_id, kind) do
    %AlbumJob{}
    |> AlbumJob.changeset(%{
      album_id: album_id,
      kind: kind,
      status: "running",
      stage: nil,
      progress: 0.0,
      message: nil,
      started_at: DateTime.utc_now(:second)
    })
    |> Repo.insert!(
      on_conflict: {:replace, [:status, :stage, :progress, :message, :started_at, :updated_at]},
      conflict_target: [:album_id, :kind]
    )

    :ok
  end

  @doc """
  A `fn stage, progress -> :ok end` that writes at most once per 1% of
  progress or ~2s, so callers can report per photo.
  """
  def reporter(album_id, kind) do
    key = {__MODULE__, album_id, kind}

    fn stage, progress ->
      now = System.monotonic_time(:millisecond)

      case Process.get(key) do
        {^stage, last, at} when progress - last < 0.01 and now - at < 2_000 ->
          :ok

        _ ->
          Process.put(key, {stage, progress, now})
          write(album_id, kind, %{stage: stage, progress: progress})
      end
    end
  end

  def finish(album_id, kind), do: write(album_id, kind, %{status: "done", progress: 1.0})

  def fail(album_id, kind, reason) do
    message = if is_binary(reason), do: reason, else: inspect(reason)
    write(album_id, kind, %{status: "failed", message: String.slice(message, 0, 500)})
  end

  @doc "True for a job still marked running that hasn't reported for a while."
  def stalled?(%AlbumJob{status: "running", updated_at: updated_at}),
    do: DateTime.diff(DateTime.utc_now(), updated_at) > @stall_after_s

  def stalled?(_job), do: false

  @doc "Seconds left, extrapolated from progress so far (nil under 2%)."
  def seconds_left(%AlbumJob{status: "running", progress: p, started_at: %DateTime{} = started})
      when is_number(p) and p >= 0.02 do
    round(DateTime.diff(DateTime.utc_now(), started) * (1 - p) / p)
  end

  def seconds_left(_job), do: nil

  defp write(album_id, kind, attrs) do
    Repo.update_all(
      from(j in AlbumJob, where: j.album_id == ^album_id and j.kind == ^kind),
      set: Keyword.new(Map.put(attrs, :updated_at, DateTime.utc_now(:second)))
    )

    :ok
  end
end
