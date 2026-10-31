defmodule Mix.Tasks.Library.Import do
  @moduledoc """
  Adds a file, or every playable file under a folder, to the media
  library at /library (see `ShubhVivahs.Library.Importer`). Already
  imported files are skipped, so re-running after adding new episodes
  only imports the new ones.

      mix library.import "Game of Thrones Season 1" --kind series
      mix library.import "Game of Thrones Season 1" --kind series --series "Game of Thrones"
      mix library.import Others --kind movie
      mix library.import path/to/clip.mp4 --kind movie --title "Another World: Making Of"
      mix library.import Music --kind song --artist "Lata Mangeshkar"
      mix library.import ep6.mkv --kind series --series "Money Heist" --season 5 --episode 6 --title "Escape Valve"
      mix library.import Show --kind series --audio eng,hin   # English main, Hindi switchable

  `--title`, `--season` and `--episode` only apply when importing a
  single file. `--audio eng,hin` keeps those audio languages: the first
  plays by default, the others are switchable in the player. The source files
  are left untouched; the library keeps its own copies under
  priv/library/.
  """

  use Mix.Task

  alias ShubhVivahs.Library.{Importer, MediaItem}

  @shortdoc "Imports series episodes, movies, or songs into the media library"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _invalid} =
      OptionParser.parse(args,
        strict: [
          kind: :string,
          title: :string,
          series: :string,
          artist: :string,
          season: :integer,
          episode: :integer,
          audio: :string
        ]
      )

    kind = opts[:kind]

    unless kind in MediaItem.kinds() do
      Mix.raise("--kind must be one of: #{Enum.join(MediaItem.kinds(), ", ")}")
    end

    case positional do
      [source] -> import(source, kind, opts)
      _ -> Mix.raise(~s(usage: mix library.import PATH --kind series|movie|song [--title T]))
    end
  end

  defp import(source, kind, opts) do
    files = Importer.importable_files(source, kind)

    if files == [], do: Mix.raise("No #{kind} files found under #{source}")

    if (opts[:title] || opts[:season] || opts[:episode]) && length(files) > 1 do
      Mix.raise("--title, --season and --episode only work when importing a single file")
    end

    import_opts = [
      title: opts[:title],
      collection: opts[:series] || opts[:artist],
      season: opts[:season],
      episode: opts[:episode],
      audio: opts[:audio] && String.split(opts[:audio], ",", trim: true)
    ]

    results =
      for file <- files do
        Mix.shell().info("→ #{Path.relative_to_cwd(file)}")
        result = Importer.import_file(file, kind, import_opts)
        Mix.shell().info("  " <> describe(result))
        elem(result, 0)
      end

    counts = Enum.frequencies(results)

    Mix.shell().info(
      "Done: #{counts[:ok] || 0} imported, #{counts[:skipped] || 0} already there, " <>
        "#{counts[:error] || 0} failed."
    )
  end

  defp describe({:ok, item}),
    do: "imported ##{item.id} #{label(item)}#{if item.has_subtitles, do: " (+ subtitles)"}"

  defp describe({:skipped, item}), do: "already imported as ##{item.id} #{label(item)}"
  defp describe({:error, reason}), do: "FAILED: #{inspect(reason)}"

  defp label(%MediaItem{season: s, episode: e} = item) when is_integer(s) and is_integer(e),
    do: "#{item.collection} S#{s}E#{e} — #{item.title}"

  defp label(%MediaItem{collection: nil, title: title}), do: title
  defp label(%MediaItem{collection: collection, title: title}), do: "#{collection} — #{title}"
end
