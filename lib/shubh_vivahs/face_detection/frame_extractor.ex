defmodule ShubhVivahs.FaceDetection.FrameExtractor do
  @moduledoc """
  Samples frames out of a video file as JPEGs, via ffmpeg. Evision's
  precompiled OpenCV build has no video-decode backend (no ffmpeg/gstreamer
  compiled in), so an external ffmpeg does the demuxing/decoding; Evision
  only ever sees still frames.
  """

  @default_fps 1

  @doc """
  Extracts frames from `video_path` at `:fps` (default #{@default_fps})
  into a fresh temp directory. Returns
  `{:ok, [%{path: path, timestamp_ms: ms}, ...]}` in playback order, or
  `{:error, reason}`.
  """
  def extract_frames(video_path, opts \\ []) do
    fps = Keyword.get(opts, :fps, @default_fps)

    with {:ok, ffmpeg} <- ffmpeg_path(),
         {:ok, dir} <- fresh_tmp_dir(),
         {:ok, _output} <- run_ffmpeg(ffmpeg, video_path, dir, fps) do
      frames =
        dir
        |> File.ls!()
        |> Enum.sort()
        |> Enum.with_index()
        |> Enum.map(fn {file, index} ->
          %{path: Path.join(dir, file), timestamp_ms: round(index * 1000 / fps)}
        end)

      {:ok, frames}
    end
  end

  defp run_ffmpeg(ffmpeg, video_path, dir, fps) do
    args = [
      "-y",
      "-i",
      video_path,
      "-vf",
      "fps=#{fps}",
      "-qscale:v",
      "2",
      Path.join(dir, "frame_%06d.jpg")
    ]

    case System.cmd(ffmpeg, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {:ffmpeg_failed, status, output}}
    end
  end

  defp fresh_tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "shubh_vivahs_face_detection_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    {:ok, dir}
  end

  @doc "Resolves the ffmpeg binary to use: system PATH first, else the bundled one."
  def ffmpeg_path do
    cond do
      path = System.find_executable("ffmpeg") ->
        {:ok, path}

      File.regular?(bundled_ffmpeg_path()) ->
        {:ok, bundled_ffmpeg_path()}

      true ->
        {:error, :ffmpeg_not_found}
    end
  end

  defp bundled_ffmpeg_path do
    Application.app_dir(:shubh_vivahs, "priv/face_detection/bin/ffmpeg")
  end
end
