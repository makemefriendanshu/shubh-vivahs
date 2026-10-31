defmodule Mix.Tasks.Photos.DetectFaces do
  @moduledoc """
  Finds the people in photo albums (see `ShubhVivahs.Photos.FaceRecognition`),
  for the album viewer's "Who's in focus?" panel.

      mix photos.detect_faces patna-reception   # one album, by slug
      mix photos.detect_faces --all             # every album

  Re-running replaces an album's people (keeping their names) and clears
  their focus votes. An album already being processed elsewhere is
  skipped unless that run has stalled.
  """

  use Mix.Task

  alias ShubhVivahs.Photos
  alias ShubhVivahs.Photos.{AlbumJobs, FaceRecognition}

  @shortdoc "Recognises the people in photo albums"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, positional, _} = OptionParser.parse(args, strict: [all: :boolean])

    albums =
      case {positional, opts[:all]} do
        {[], true} -> Photos.list_albums(:all)
        {[slug], _} -> [Photos.get_album_by_slug(slug) || Mix.raise("No album #{slug}")]
        _ -> Mix.raise("usage: mix photos.detect_faces ALBUM_SLUG | --all")
      end

    for album <- albums do
      job = AlbumJobs.get(album.id, "recognition")

      if job && job.status == "running" && not AlbumJobs.stalled?(job) do
        Mix.shell().info("#{album.title}: already running elsewhere, skipped")
      else
        Mix.shell().info("#{album.title}: detecting faces…")
        start = System.monotonic_time(:second)

        case FaceRecognition.run(album) do
          {:ok, counts} ->
            Mix.shell().info(
              "#{album.title}: #{counts.people} people from #{counts.faces} faces in " <>
                "#{counts.photos} photos (#{System.monotonic_time(:second) - start}s)"
            )

          {:error, reason} ->
            Mix.shell().error("#{album.title}: failed — #{inspect(reason)}")
        end
      end
    end
  end
end
