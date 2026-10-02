defmodule ShubhVivahs.VideoPreview do
  @moduledoc """
  Generates and caches lower-bitrate proxies of a movie's source video (a
  720p "preview" and a 360p "minimal" tier), so it stays watchable over
  bandwidth-constrained connections (e.g. the ngrok tunnel, which tops out
  well below the bitrate of raw camera footage).
  """

  alias ShubhVivahs.FaceDetection.Movie

  @preview_scale "-2:720"
  @preview_bitrate "2500k"
  @preview_audio_bitrate "128k"

  @minimal_scale "-2:360"
  @minimal_bitrate "700k"
  @minimal_audio_bitrate "64k"

  @doc "Path the cached preview for this movie would live at, whether or not it exists yet."
  @spec preview_path(Movie.t()) :: String.t()
  def preview_path(%Movie{id: id}) do
    Path.join(previews_dir(), "#{id}.mp4")
  end

  @doc "Path the cached minimal-quality proxy for this movie would live at, whether or not it exists yet."
  @spec minimal_path(Movie.t()) :: String.t()
  def minimal_path(%Movie{id: id}) do
    Path.join(previews_dir(), "#{id}_minimal.mp4")
  end

  @doc "Whether a cached preview has already been generated for this movie."
  @spec preview_ready?(Movie.t()) :: boolean
  def preview_ready?(movie) do
    movie |> preview_path() |> File.regular?()
  end

  @doc "Whether a cached minimal-quality proxy has already been generated for this movie."
  @spec minimal_ready?(Movie.t()) :: boolean
  def minimal_ready?(movie) do
    movie |> minimal_path() |> File.regular?()
  end

  @doc """
  Normalizes a quality picker's raw selection ("source", "preview", or
  "minimal") to the quality that will actually be used: "minimal"/"preview"
  only ever come back when that tier has been generated, falling back down
  through preview to "source" otherwise (covers `nil`/unrecognized values
  too, e.g. no explicit choice made yet).
  """
  @spec normalize_quality(Movie.t(), String.t() | nil) :: String.t()
  def normalize_quality(_movie, "source"), do: "source"

  def normalize_quality(movie, "minimal") do
    if minimal_ready?(movie), do: "minimal", else: normalize_quality(movie, nil)
  end

  def normalize_quality(movie, _quality) do
    if preview_ready?(movie), do: "preview", else: "source"
  end

  @doc "Resolves a quality picker's raw selection to the file path it maps to."
  @spec resolve_quality(Movie.t(), String.t() | nil) :: String.t()
  def resolve_quality(movie, quality) do
    case normalize_quality(movie, quality) do
      "source" -> movie.path
      "preview" -> preview_path(movie)
      "minimal" -> minimal_path(movie)
    end
  end

  @doc """
  Transcodes the movie's source file into a cached 720p/#{@preview_bitrate} preview.
  Overwrites any existing preview. Returns the preview path.
  """
  @spec generate!(Movie.t()) :: String.t()
  def generate!(movie) do
    transcode!(
      movie,
      preview_path(movie),
      @preview_scale,
      @preview_bitrate,
      @preview_audio_bitrate
    )
  end

  @doc """
  Transcodes the movie's source file into a cached 360p/#{@minimal_bitrate} proxy
  for very bandwidth-constrained playback. Overwrites any existing one. Returns the path.
  """
  @spec generate_minimal!(Movie.t()) :: String.t()
  def generate_minimal!(movie) do
    transcode!(
      movie,
      minimal_path(movie),
      @minimal_scale,
      @minimal_bitrate,
      @minimal_audio_bitrate
    )
  end

  defp transcode!(%Movie{path: source}, dest, scale, video_bitrate, audio_bitrate) do
    File.mkdir_p!(previews_dir())
    tmp = dest <> ".tmp"

    args = [
      "-y",
      "-i",
      source,
      "-vf",
      "scale=#{scale}",
      "-c:v",
      "libx264",
      "-preset",
      "veryfast",
      "-b:v",
      video_bitrate,
      "-maxrate",
      video_bitrate,
      "-bufsize",
      bufsize(video_bitrate),
      "-c:a",
      "aac",
      "-b:a",
      audio_bitrate,
      "-movflags",
      "+faststart",
      "-f",
      "mp4",
      tmp
    ]

    {output, exit_code} = System.cmd(ffmpeg_path(), args, stderr_to_stdout: true)

    if exit_code == 0 do
      File.rename!(tmp, dest)
      dest
    else
      File.rm(tmp)
      raise "ffmpeg exited with status #{exit_code}:\n#{output}"
    end
  end

  defp bufsize(bitrate) do
    {kbps, "k"} = Integer.parse(bitrate)
    "#{kbps * 2}k"
  end

  defp previews_dir do
    Path.join(:code.priv_dir(:shubh_vivahs), "face_detection/previews")
  end

  defp ffmpeg_path do
    bundled = Path.join(:code.priv_dir(:shubh_vivahs), "face_detection/bin/ffmpeg")
    if File.regular?(bundled), do: bundled, else: "ffmpeg"
  end
end
