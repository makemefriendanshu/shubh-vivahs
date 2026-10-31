defmodule ShubhVivahs.QualityVersions do
  @moduledoc """
  Builds everything the player's quality picker and download menu offer
  beyond the original file, in one go — the "Generate quality versions"
  button on AdminMoviePage:

    1. 720p "data saver" proxy (`VideoPreview.generate!/2`) — skipped when
       the original is already 720p or smaller, where it would only be a
       bigger re-encode of the same picture (most library episodes)
    2. 360p "minimal" proxy (`VideoPreview.generate_minimal!/2`)
    3. download parts (`VideoSegments.generate!/2`) for every quality

  Progress is recorded as the movie's "versions" job (see `MovieJobs`).
  Regenerating replaces whatever was there before.
  """

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.MovieJobs
  alias ShubhVivahs.VideoMetadata
  alias ShubhVivahs.VideoPreview
  alias ShubhVivahs.VideoSegments

  @preview_max_source_height 720

  @doc "Whether the 720p proxy is worth making for `movie` (its original is taller than 720p)."
  def preview_worthwhile?(%Movie{} = movie) do
    case VideoMetadata.fetch(movie) do
      %{height: height} when is_integer(height) -> height > @preview_max_source_height
      _unknown -> true
    end
  end

  @doc "Runs every step for `movie`. Returns `:ok` or `{:error, reason}`."
  @spec generate(Movie.t()) :: :ok | {:error, term}
  def generate(%Movie{} = movie) do
    MovieJobs.start(movie.id, "versions")
    report = MovieJobs.reporter(movie.id, "versions")

    # Share of the bar each step gets; without the 720p step the 360p one
    # takes its share too, so the time-left estimate isn't thrown by a jump.
    {preview_share, minimal_share} =
      if preview_worthwhile?(movie), do: {0.45, 0.4}, else: {0.0, 0.85}

    try do
      if preview_share > 0 do
        report.("Making 720p data-saver version", 0.0)

        VideoPreview.generate!(movie,
          on_progress: &report.("Making 720p data-saver version", &1 * preview_share)
        )

        VideoMetadata.forget(movie, :preview)
      end

      report.("Making 360p minimal version", preview_share)

      VideoPreview.generate_minimal!(movie,
        on_progress: &report.("Making 360p minimal version", preview_share + &1 * minimal_share)
      )

      VideoMetadata.forget(movie, :minimal)

      qualities =
        ["source"] ++
          if(VideoPreview.preview_ready?(movie), do: ["preview"], else: []) ++
          if VideoPreview.minimal_ready?(movie), do: ["minimal"], else: []

      qualities
      |> Enum.with_index()
      |> Enum.each(fn {quality, index} ->
        report.("Cutting download parts", 0.85 + 0.15 * index / length(qualities))
        VideoSegments.generate!(movie, quality)
      end)

      MovieJobs.finish(movie.id, "versions")
      :ok
    rescue
      exception ->
        message = Exception.message(exception)
        MovieJobs.fail(movie.id, "versions", message)
        {:error, message}
    end
  end
end
