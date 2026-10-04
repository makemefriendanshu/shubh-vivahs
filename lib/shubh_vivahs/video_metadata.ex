defmodule ShubhVivahs.VideoMetadata do
  @moduledoc """
  Probes a movie's duration, resolution, and file size via ffmpeg (reads
  the container header only, no decoding), and caches the result on disk
  so /premiere doesn't re-spawn ffmpeg on every page view.
  """

  alias ShubhVivahs.FaceDetection.{FrameExtractor, Movie}
  alias ShubhVivahs.VideoPreview

  @type t :: %{
          duration_ms: non_neg_integer | nil,
          width: pos_integer | nil,
          height: pos_integer | nil,
          size_bytes: non_neg_integer
        }

  @doc "Returns cached metadata for this movie's source file, probing and caching it on first call."
  @spec fetch(Movie.t()) :: t()
  def fetch(movie) do
    fetch_path(movie.path, cache_path(movie))
  end

  @doc """
  Returns cached metadata for this movie's lower-bitrate preview proxy, or
  `nil` if no preview has been generated for it yet.
  """
  @spec fetch_preview(Movie.t()) :: t() | nil
  def fetch_preview(movie) do
    if VideoPreview.preview_ready?(movie) do
      fetch_path(VideoPreview.preview_path(movie), preview_cache_path(movie))
    end
  end

  @doc """
  Returns cached metadata for this movie's minimal-quality proxy, or
  `nil` if no minimal proxy has been generated for it yet.
  """
  @spec fetch_minimal(Movie.t()) :: t() | nil
  def fetch_minimal(movie) do
    if VideoPreview.minimal_ready?(movie) do
      fetch_path(VideoPreview.minimal_path(movie), minimal_cache_path(movie))
    end
  end

  @doc "One-line human summary, e.g. \"39 min · 1920x1080 · 5.7 GB\"."
  @spec describe(t()) :: String.t()
  def describe(metadata) do
    [
      format_duration(metadata.duration_ms),
      format_resolution(metadata),
      format_size(metadata.size_bytes)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc "One-line resolution/size summary, e.g. \"1920x1080 · 5.7 GB\", for a quality picker."
  @spec describe_quality(t()) :: String.t()
  def describe_quality(metadata) do
    [format_resolution(metadata), format_size(metadata.size_bytes)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc """
  Probes a media file's duration directly, without the movie-keyed caching
  `fetch/1` and friends use — for one-off durations like a video segment's.
  """
  @spec probe_duration_ms(String.t()) :: non_neg_integer | nil
  def probe_duration_ms(path) do
    case FrameExtractor.ffmpeg_path() do
      {:ok, ffmpeg} ->
        {output, _status} = System.cmd(ffmpeg, ["-i", path], stderr_to_stdout: true)
        output |> parse_duration() |> Map.get(:duration_ms)

      {:error, :ffmpeg_not_found} ->
        nil
    end
  end

  @spec format_duration(non_neg_integer | nil) :: String.t() | nil
  def format_duration(nil), do: nil

  def format_duration(duration_ms) do
    total_seconds = div(duration_ms, 1000)
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)

    if hours > 0 do
      "#{hours}h #{minutes}m"
    else
      "#{minutes} min"
    end
  end

  @spec format_resolution(t()) :: String.t() | nil
  def format_resolution(%{width: nil}), do: nil
  def format_resolution(%{height: nil}), do: nil
  def format_resolution(%{width: width, height: height}), do: "#{width}x#{height}"

  @spec format_size(non_neg_integer) :: String.t()
  def format_size(size_bytes) when size_bytes >= 1_000_000_000 do
    "#{Float.round(size_bytes / 1_000_000_000, 1)} GB"
  end

  def format_size(size_bytes) do
    "#{Float.round(size_bytes / 1_000_000, 1)} MB"
  end

  defp fetch_path(path, cache_path) do
    case File.read(cache_path) do
      {:ok, json} -> decode(json)
      {:error, _} -> probe_and_cache(path, cache_path)
    end
  end

  defp probe_and_cache(path, cache_path) do
    metadata = probe(path)
    File.mkdir_p!(cache_dir())
    File.write!(cache_path, encode(metadata))
    metadata
  end

  defp probe(path) do
    base = %{size_bytes: file_size(path), duration_ms: nil, width: nil, height: nil}

    case FrameExtractor.ffmpeg_path() do
      {:ok, ffmpeg} ->
        {output, _status} = System.cmd(ffmpeg, ["-i", path], stderr_to_stdout: true)
        base |> Map.merge(parse_duration(output)) |> Map.merge(parse_resolution(output))

      {:error, :ffmpeg_not_found} ->
        base
    end
  end

  defp parse_duration(output) do
    case Regex.run(~r/Duration: (\d+):(\d+):(\d+\.\d+)/, output) do
      [_, hours, minutes, seconds] ->
        ms =
          (String.to_integer(hours) * 3600 + String.to_integer(minutes) * 60 +
             String.to_float(seconds)) * 1000

        %{duration_ms: round(ms)}

      nil ->
        %{}
    end
  end

  defp parse_resolution(output) do
    case Regex.run(~r/Video:.*?(\d{2,5})x(\d{2,5})/, output) do
      [_, width, height] -> %{width: String.to_integer(width), height: String.to_integer(height)}
      nil -> %{}
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp cache_dir do
    Path.join(:code.priv_dir(:shubh_vivahs), "face_detection/movie_metadata")
  end

  defp cache_path(%Movie{id: id}) do
    Path.join(cache_dir(), "#{id}.json")
  end

  defp preview_cache_path(%Movie{id: id}) do
    Path.join(cache_dir(), "#{id}_preview.json")
  end

  defp minimal_cache_path(%Movie{id: id}) do
    Path.join(cache_dir(), "#{id}_minimal.json")
  end

  defp encode(metadata), do: Jason.encode!(metadata)

  defp decode(json) do
    json
    |> Jason.decode!()
    |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
  end
end
