defmodule Mix.Tasks.Library.DetectFaces do
  @moduledoc """
  Runs face detection on media library videos (series episodes and
  movies) so they get the same "Who's in focus?" voting and face naming
  as wedding films — see `ShubhVivahs.Library.detect_faces/1`. Slow: it
  samples one frame every 2 seconds, so a one-hour episode is 1,800 frames.

      mix library.detect_faces            # every video not detected yet
      mix library.detect_faces --id 14    # one library item (re-runs it)
      mix library.detect_faces --all      # re-run everything

  Without `--id`/`--all`, videos already scanned or marked "processing"
  (being scanned from the admin page) are skipped, re-checked right
  before each one.

  Each video's faces are saved as soon as it finishes, so stopping
  partway keeps the finished ones and the next run picks up the rest.
  """

  use Mix.Task

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.Library
  alias ShubhVivahs.MovieJobs
  alias ShubhVivahs.Repo

  @shortdoc "Runs face detection on media library videos"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _positional, _invalid} =
      OptionParser.parse(args, strict: [id: :integer, all: :boolean])

    items =
      case opts[:id] do
        nil ->
          Library.list_ready_videos()
          |> Enum.map(fn item ->
            {:ok, item} = Library.ensure_movie(item)
            item
          end)
          |> Enum.filter(&(opts[:all] || not detected?(&1)))

        id ->
          [Library.get_item(id) || Mix.raise("No library item ##{id}")]
      end

    Mix.shell().info("#{length(items)} video(s) to scan.")

    for {item, index} <- Enum.with_index(items, 1) do
      Mix.shell().info("[#{index}/#{length(items)}] #{Library.movie_title(item)}")
      started = System.monotonic_time(:second)

      # A long run outlasts the list it started with: re-check right before
      # each video, so one an admin has since scanned (and maybe labelled)
      # from AdminMoviePage, or that's being scanned there now, is left alone.
      case skip_reason(item, opts[:all] || opts[:id] != nil) do
        nil -> detect(item, started)
        reason -> Mix.shell().info("  skipped: #{reason}")
      end
    end
  end

  # `--all`/`--id` force a run regardless (e.g. to clear a "processing"
  # status left behind by a run that was killed).
  defp skip_reason(_item, true = _forced?), do: nil

  defp skip_reason(item, _forced?) do
    case Repo.get(Movie, item.movie_id) do
      %Movie{status: "processing", id: id} ->
        # A run whose process died (OOM kill, stopped service) leaves
        # "processing" behind; once it's stopped reporting, take it over.
        unless MovieJobs.stalled?(MovieJobs.get(id, "recognition")), do: "being scanned elsewhere"

      %Movie{status: "done"} ->
        "already scanned"

      _movie ->
        nil
    end
  end

  defp detect(item, started) do
    case Library.detect_faces(item) do
      {:ok, movie} ->
        elapsed = System.monotonic_time(:second) - started
        Mix.shell().info("  #{length(movie.faces)} unique face(s) in #{format(elapsed)}")

      {:error, reason} ->
        Mix.shell().error("  FAILED: #{inspect(reason)}")
    end
  end

  defp detected?(%{movie_id: movie_id}) do
    match?(%Movie{status: "done"}, Repo.get(Movie, movie_id))
  end

  defp format(seconds) when seconds < 60, do: "#{seconds}s"
  defp format(seconds), do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
end
