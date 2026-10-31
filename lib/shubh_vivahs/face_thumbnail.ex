defmodule ShubhVivahs.FaceThumbnail do
  @moduledoc """
  Generates and caches a small cropped thumbnail for a detected face, so
  the admin scene browser can show *who* a face is rather than just an id.
  Picks the face's highest-confidence detection, grabs that single frame
  from the source video via ffmpeg, and crops around its bounding box.
  """

  alias ShubhVivahs.FaceDetection.{Face, FrameExtractor}

  @size {200, 200}
  @padding_ratio 0.25

  @doc "Path the cached thumbnail for this face would live at, whether or not it exists yet."
  @spec thumbnail_path(Face.t()) :: String.t()
  def thumbnail_path(%Face{id: id}) do
    Path.join(thumbnails_dir(), "#{id}.jpg")
  end

  @doc "Whether a cached thumbnail has already been generated for this face."
  @spec thumbnail_ready?(Face.t()) :: boolean
  def thumbnail_ready?(face) do
    face |> thumbnail_path() |> File.regular?()
  end

  @doc """
  Generates and caches a thumbnail for `face`, which must be preloaded
  with `:movie` and `:detections`. Returns the thumbnail path.
  """
  @spec generate!(Face.t()) :: String.t()
  def generate!(%Face{movie: movie, detections: [_ | _] = detections} = face) do
    File.mkdir_p!(thumbnails_dir())
    detection = Enum.max_by(detections, & &1.confidence)
    frame_path = extract_frame!(movie.path, detection.frame_time_ms)

    try do
      dest = thumbnail_path(face)

      resized =
        frame_path
        |> Evision.imread()
        |> crop_with_padding(detection)
        |> Evision.resize(@size)

      Evision.imwrite(dest, resized)

      dest
    after
      File.rm(frame_path)
    end
  end

  defp extract_frame!(video_path, frame_time_ms) do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "shubh_vivahs_face_thumbnail_#{:erlang.unique_integer([:positive])}.jpg"
      )

    args = [
      "-y",
      "-ss",
      # Plain string interpolation renders a "round" float like 2300.0 as
      # "2.3e3" (Elixir's shortest round-trip representation, picked
      # because it's fewer characters) — ffmpeg's -ss rejects scientific
      # notation. float_to_binary with a fixed decimal count always
      # produces plain notation instead.
      :erlang.float_to_binary(frame_time_ms / 1000, decimals: 3),
      "-i",
      video_path,
      "-vframes",
      "1",
      "-q:v",
      "2",
      tmp
    ]

    case System.cmd(ffmpeg_path!(), args, stderr_to_stdout: true) do
      {_output, 0} -> tmp
      {output, status} -> raise "ffmpeg exited with status #{status}:\n#{output}"
    end
  end

  defp crop_with_padding(img, %{bbox_x: x, bbox_y: y, bbox_w: w, bbox_h: h}) do
    {img_h, img_w, _} = Evision.Mat.shape(img)
    pad_x = w * @padding_ratio
    pad_y = h * @padding_ratio

    x1 = max(0, round(x - pad_x))
    y1 = max(0, round(y - pad_y))
    x2 = min(img_w, round(x + w + pad_x))
    y2 = min(img_h, round(y + h + pad_y))

    Evision.Mat.roi(img, {x1, y1, x2 - x1, y2 - y1})
  end

  defp thumbnails_dir do
    Path.join(:code.priv_dir(:shubh_vivahs), "face_detection/thumbnails")
  end

  defp ffmpeg_path! do
    case FrameExtractor.ffmpeg_path() do
      {:ok, path} -> path
      {:error, :ffmpeg_not_found} -> raise "ffmpeg not found — run `mix face_detection.setup`"
    end
  end
end
