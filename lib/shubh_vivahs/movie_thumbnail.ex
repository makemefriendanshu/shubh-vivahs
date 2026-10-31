defmodule ShubhVivahs.MovieThumbnail do
  @moduledoc """
  Generates and caches a poster-frame thumbnail for a movie, grabbed from
  a few seconds into the video via ffmpeg, so /premiere has something to
  show besides a bare title.
  """

  alias ShubhVivahs.FaceDetection.{FrameExtractor, Movie}

  @offset_seconds 5

  # Downscaled from the source's full resolution (1080p+ frames came out at
  # ~400 KB) — big enough for the full-width hero carousel, small enough
  # that a page of cards doesn't saturate a slow uplink.
  @max_width 960

  @doc "Path the cached thumbnail for this movie would live at, whether or not it exists yet."
  @spec thumbnail_path(Movie.t()) :: String.t()
  def thumbnail_path(%Movie{id: id}) do
    Path.join(thumbnails_dir(), "#{id}.jpg")
  end

  @doc "Whether a cached thumbnail has already been generated for this movie."
  @spec thumbnail_ready?(Movie.t()) :: boolean
  def thumbnail_ready?(movie) do
    movie |> thumbnail_path() |> File.regular?()
  end

  @doc "Generates and caches a poster-frame thumbnail for `movie`. Returns the thumbnail path."
  @spec generate!(Movie.t()) :: String.t()
  def generate!(%Movie{path: source} = movie) do
    File.mkdir_p!(thumbnails_dir())
    dest = thumbnail_path(movie)

    args = [
      "-y",
      "-ss",
      "#{@offset_seconds}",
      "-i",
      source,
      "-vframes",
      "1",
      "-vf",
      "scale='min(#{@max_width},iw)':-2",
      "-q:v",
      "5",
      dest
    ]

    case System.cmd(ffmpeg_path!(), args, stderr_to_stdout: true) do
      {_output, 0} -> dest
      {output, status} -> raise "ffmpeg exited with status #{status}:\n#{output}"
    end
  end

  defp thumbnails_dir do
    Path.join(:code.priv_dir(:shubh_vivahs), "face_detection/movie_thumbnails")
  end

  defp ffmpeg_path! do
    case FrameExtractor.ffmpeg_path() do
      {:ok, path} -> path
      {:error, :ffmpeg_not_found} -> raise "ffmpeg not found — run `mix face_detection.setup`"
    end
  end
end
