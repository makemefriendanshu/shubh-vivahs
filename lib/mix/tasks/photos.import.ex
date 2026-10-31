defmodule Mix.Tasks.Photos.Import do
  @moduledoc """
  Adds a folder of photos (JPEGs, searched recursively) to a photo album in
  the wedding gallery, creating the album if needed (see
  `ShubhVivahs.Photos.Importer`). The originals are **moved** into
  priv/photos/; re-running skips photos already imported.

      mix photos.import "Marriage-Photos/Patna Reception" --title "Patna Reception"

  New albums start private — make them public from their admin page.
  """

  use Mix.Task

  @shortdoc "Imports a folder of photos into a gallery album"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, positional, _} = OptionParser.parse(args, strict: [title: :string])

    case {positional, opts[:title]} do
      {[source], title} when is_binary(title) ->
        unless File.dir?(source), do: Mix.raise("#{source} is not a folder")
        start = System.monotonic_time(:second)

        {:ok, album, counts} =
          ShubhVivahs.Photos.Importer.import_dir(source, title, fn done, total ->
            if rem(done, 50) == 0 or done == total,
              do: Mix.shell().info("  #{done}/#{total} copies made")
          end)

        Mix.shell().info(
          "Album \"#{album.title}\" (##{album.id}, #{ShubhVivahs.Photos.album_path(album)}): " <>
            "#{counts.imported} imported, #{counts.skipped} already there, #{counts.failed} failed " <>
            "in #{System.monotonic_time(:second) - start}s"
        )

      _ ->
        Mix.raise(~s(usage: mix photos.import FOLDER --title "Album title"))
    end
  end
end
