defmodule Mix.Tasks.FaceDetection.Ingest do
  @moduledoc """
  Manual verification hook for the face detection service: runs the
  full ingest → detect → cluster → persist pipeline against a real
  video file and prints a summary.

      mix face_detection.ingest path/to/video.mp4
      mix face_detection.ingest path/to/video.mp4 --title "Reception"
  """

  use Mix.Task

  @shortdoc "Ingests a video and clusters its unique faces"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _invalid} = OptionParser.parse(args, strict: [title: :string])

    case positional do
      [video_path] ->
        ingest(video_path, opts)

      _ ->
        Mix.raise("usage: mix face_detection.ingest PATH [--title TITLE]")
    end
  end

  defp ingest(video_path, opts) do
    case ShubhVivahs.FaceDetection.ingest_video(video_path, opts) do
      {:ok, movie} ->
        Mix.shell().info(
          "Movie ##{movie.id} (#{movie.status}): #{length(movie.faces)} unique face(s)"
        )

        for face <- movie.faces do
          Mix.shell().info("  face ##{face.id}: #{length(face.detections)} detection(s)")
        end

      {:error, reason} ->
        Mix.raise("ingest failed: #{inspect(reason)}")
    end
  end
end
