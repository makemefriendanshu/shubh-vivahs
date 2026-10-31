defmodule Mix.Tasks.Library.Reorganize do
  @moduledoc """
  Moves media library files into readable folders (see
  `ShubhVivahs.Library.relative_media_path/2`), updating the database to
  match, so playback, subtitles, and face data keep working:

      mix library.reorganize            # move everything
      mix library.reorganize --dry-run  # just list what would move

  Safe to re-run: files already in place are left alone. New imports are
  stored this way already.
  """

  use Mix.Task

  alias ShubhVivahs.Library
  alias ShubhVivahs.Library.MediaItem
  alias ShubhVivahs.Repo

  @shortdoc "Groups media library files into series/season/title folders"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, strict: [dry_run: :boolean])

    results =
      for item <- Repo.all(MediaItem) |> Enum.sort_by(& &1.path) do
        if opts[:dry_run] do
          new = Library.relative_media_path(item, Path.extname(item.path || ""))
          if new != item.path, do: Mix.shell().info("#{item.path}\n  -> #{new}")
          :dry
        else
          case Library.reorganize(item) do
            {:ok, :moved, moved} ->
              Mix.shell().info("moved  #{moved.path}")
              :moved

            {:ok, :unchanged, _} ->
              :unchanged

            {:error, reason} ->
              Mix.shell().error("FAILED #{item.path}: #{inspect(reason)}")
              :error
          end
        end
      end

    counts = Enum.frequencies(results)

    Mix.shell().info(
      "Done: #{counts[:moved] || 0} moved, #{counts[:unchanged] || 0} already in place, " <>
        "#{counts[:error] || 0} failed."
    )
  end
end
