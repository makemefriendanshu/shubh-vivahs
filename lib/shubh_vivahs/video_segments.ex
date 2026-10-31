defmodule ShubhVivahs.VideoSegments do
  @moduledoc """
  Splits a movie into ~10 independently-playable segments via ffmpeg's
  segment muxer with stream copy (no re-encoding, so it's fast and
  lossless). Unlike a raw byte-range slice, each segment is a
  self-contained video file that can be downloaded and played on its
  own, without needing to be joined with the others first.

  Cuts can only land on keyframes, so the actual segment count/lengths
  vary slightly around the 10-way split — callers should read back
  whatever `list/1` returns rather than assuming exactly 10.
  """

  alias ShubhVivahs.FaceDetection.{FrameExtractor, Movie}
  alias ShubhVivahs.VideoMetadata
  alias ShubhVivahs.VideoPreview

  @target_segment_count 10

  @doc "Lists the cached segment paths for this movie/quality, in order. Empty if not generated yet."
  @spec list(Movie.t(), String.t()) :: [String.t()]
  def list(movie, quality) do
    dir = segments_dir(movie, quality)

    case File.ls(dir) do
      {:ok, files} -> files |> Enum.sort() |> Enum.map(&Path.join(dir, &1))
      {:error, _} -> []
    end
  end

  @doc "Returns the cached segments for this movie/quality, generating them first if needed."
  @spec ensure_generated!(Movie.t(), String.t()) :: [String.t()]
  def ensure_generated!(movie, quality) do
    case list(movie, quality) do
      [] -> generate!(movie, quality)
      segments -> segments
    end
  end

  @doc """
  Returns each segment's start offset in ms within the movie's own timeline
  (same order as `list/2`) — each part file's internal clock restarts at 0
  (`-reset_timestamps 1`), so the "who's in focus" panel needs this to map a
  part's `currentTime` back to the movie-wide scene boundaries it matches
  against. Segments generated as `-c copy` cuts on the source's own keyframes
  vary slightly around the nominal split, so offsets are probed from the
  actual segment files (and cached) rather than assumed to be a uniform
  `segment_seconds(movie) * (part - 1)`.
  """
  @spec offsets_ms(Movie.t(), String.t()) :: [non_neg_integer]
  def offsets_ms(movie, quality) do
    segments = ensure_generated!(movie, quality)
    cache = offsets_cache_path(movie, quality)

    case File.read(cache) do
      {:ok, json} -> Jason.decode!(json)
      {:error, _} -> compute_and_cache_offsets(segments, cache)
    end
  end

  defp compute_and_cache_offsets(segments, cache_path) do
    {offsets, _end_ms} =
      Enum.map_reduce(segments, 0, fn path, start_ms ->
        {start_ms, start_ms + (VideoMetadata.probe_duration_ms(path) || 0)}
      end)

    File.write!(cache_path, Jason.encode!(offsets))
    offsets
  end

  @doc "Splits `movie` into fresh segments at the given quality, replacing any previously cached ones."
  @spec generate!(Movie.t(), String.t()) :: [String.t()]
  def generate!(movie, quality) do
    source = VideoPreview.resolve_quality(movie, quality)
    dir = segments_dir(movie, quality)
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    File.rm(offsets_cache_path(movie, quality))

    args = [
      "-y",
      "-i",
      source,
      "-c",
      "copy",
      "-map",
      "0",
      "-f",
      "segment",
      "-segment_time",
      "#{segment_seconds(movie)}",
      "-reset_timestamps",
      "1",
      Path.join(dir, "part%03d.mp4")
    ]

    case System.cmd(ffmpeg_path!(), args, stderr_to_stdout: true) do
      {_output, 0} ->
        list(movie, quality)

      {output, status} ->
        File.rm_rf!(dir)
        raise "ffmpeg exited with status #{status}:\n#{output}"
    end
  end

  defp segment_seconds(movie) do
    case VideoMetadata.fetch(movie) do
      %{duration_ms: duration_ms} when is_integer(duration_ms) and duration_ms > 0 ->
        max(1, div(duration_ms, 1000 * @target_segment_count))

      _ ->
        60
    end
  end

  defp segments_dir(%Movie{id: id}, quality) do
    Path.join([:code.priv_dir(:shubh_vivahs), "face_detection/movie_segments", "#{id}", quality])
  end

  # A sibling of segments_dir/2, not a file inside it — list/2 lists every
  # file in that directory as a segment, so the cache can't live there too.
  defp offsets_cache_path(%Movie{id: id}, quality) do
    Path.join([
      :code.priv_dir(:shubh_vivahs),
      "face_detection/movie_segments",
      "#{id}",
      "#{quality}_offsets.json"
    ])
  end

  defp ffmpeg_path! do
    case FrameExtractor.ffmpeg_path() do
      {:ok, path} -> path
      {:error, :ffmpeg_not_found} -> raise "ffmpeg not found — run `mix face_detection.setup`"
    end
  end
end
