defmodule Mix.Tasks.Premiere.GeneratePreviews do
  @moduledoc """
  Generates cached low-bitrate proxies for every movie that doesn't have one
  yet — a 720p/2.5Mbps "preview" and a 360p/700kbps "minimal" tier — so
  /premiere stays watchable over bandwidth-constrained connections (e.g. the
  ngrok tunnel).

      mix premiere.generate_previews
  """

  use Mix.Task

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.Repo
  alias ShubhVivahs.VideoPreview

  @shortdoc "Generates cached low-bitrate preview proxies for movies"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    movies = Repo.all(Movie)

    movies
    |> Enum.reject(&VideoPreview.preview_ready?/1)
    |> Enum.each(fn movie ->
      Mix.shell().info("Generating preview for ##{movie.id} (#{movie.title})...")
      VideoPreview.generate!(movie)
      Mix.shell().info("  done: #{VideoPreview.preview_path(movie)}")
    end)

    movies
    |> Enum.reject(&VideoPreview.minimal_ready?/1)
    |> Enum.each(fn movie ->
      Mix.shell().info("Generating minimal proxy for ##{movie.id} (#{movie.title})...")
      VideoPreview.generate_minimal!(movie)
      Mix.shell().info("  done: #{VideoPreview.minimal_path(movie)}")
    end)
  end
end
