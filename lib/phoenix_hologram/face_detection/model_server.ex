defmodule PhoenixHologram.FaceDetection.ModelServer do
  @moduledoc """
  Owns the YuNet face detector and SFace face-embedding models (loaded
  from `priv/face_detection/models/`, fetched by `mix face_detection.setup`)
  and runs them against single frames. Models are loaded lazily, on first
  use, so the app can boot fine on a machine that hasn't run the setup
  task yet — only actual detection calls fail until it has.
  """

  use GenServer

  @yunet_model "priv/face_detection/models/face_detection_yunet_2023mar.onnx"
  @sface_model "priv/face_detection/models/face_recognition_sface_2021dec.onnx"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Detects faces in the image at `image_path`. Returns
  `{:ok, [%{bbox: {x, y, w, h}, confidence: float, embedding: [float]}]}`,
  or `{:error, reason}` — notably `{:error, :models_not_found}` if
  `mix face_detection.setup` hasn't been run yet.
  """
  def detect_faces(image_path) do
    GenServer.call(__MODULE__, {:detect_faces, image_path}, :infinity)
  end

  @impl true
  def init(_opts), do: {:ok, %{detector: nil, recognizer: nil, input_size: nil}}

  @impl true
  def handle_call({:detect_faces, image_path}, _from, state) do
    with {:ok, state} <- ensure_recognizer(state),
         %Evision.Mat{} = img <- Evision.imread(image_path) do
      {faces, state} = detect_with_rotation_fallback(state, img)
      {:reply, {:ok, faces}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # (degrees, cv2 rotate code or nil for "as-is") — tried in this order.
  @rotations [
    {0, nil},
    {90, Evision.Constant.cv_ROTATE_90_CLOCKWISE()},
    {180, Evision.Constant.cv_ROTATE_180()},
    {270, Evision.Constant.cv_ROTATE_90_COUNTERCLOCKWISE()}
  ]

  # YuNet expects roughly upright faces. A phone video shot sideways (no
  # `rotate` tag, and no display-matrix side data either — confirmed
  # against a real sideways clip that this ffmpeg build gives no rotation
  # hint for at all) would otherwise silently detect zero faces on every
  # single frame. Try the frame as-is first — free for the common case,
  # already-upright footage — and only pay for 90/180/270 rotated
  # re-attempts when that comes up empty. A hit's bbox gets remapped back
  # into the *original* frame's coordinate space before returning: every
  # downstream consumer (FaceThumbnail, scene bbox overlays) re-reads
  # that original, un-rotated frame, so a bbox found in a rotated copy is
  # meaningless to them without this.
  defp detect_with_rotation_fallback(state, img) do
    {h, w, _} = Evision.Mat.shape(img)

    Enum.reduce_while(@rotations, {[], state}, fn {degrees, code}, {_faces, state} ->
      rotated = if code, do: Evision.rotate(img, code), else: img
      rotated_size = if code in [nil, Evision.Constant.cv_ROTATE_180()], do: {w, h}, else: {h, w}

      case ensure_detector(state, rotated_size) do
        {:ok, state} ->
          case detect(state, rotated) do
            [] -> {:cont, {[], state}}
            faces -> {:halt, {Enum.map(faces, &remap_bbox(&1, degrees, w, h)), state}}
          end

        {:error, _reason} ->
          {:halt, {[], state}}
      end
    end)
  end

  defp remap_bbox(face, 0, _w, _h), do: face

  defp remap_bbox(%{bbox: {bx, by, bw, bh}} = face, 180, w, h),
    do: %{face | bbox: {w - (bx + bw), h - (by + bh), bw, bh}}

  defp remap_bbox(%{bbox: {bx, by, bw, bh}} = face, 90, _w, h),
    do: %{face | bbox: {by, h - bx - bw, bh, bw}}

  defp remap_bbox(%{bbox: {bx, by, bw, bh}} = face, 270, w, _h),
    do: %{face | bbox: {w - by - bh, bx, bh, bw}}

  defp detect(%{detector: detector, recognizer: recognizer}, img) do
    case Evision.FaceDetectorYN.detect(detector, img) do
      {_n, %Evision.Mat{} = faces} -> extract_faces(faces, recognizer, img)
      {_n, {:error, _}} -> []
    end
  end

  defp extract_faces(faces, recognizer, img) do
    {rows, cols} = Evision.Mat.shape(faces)

    for row_index <- 0..(rows - 1) do
      row = Evision.Mat.roi(faces, {0, row_index, cols, 1})

      [x, y, w, h | _landmarks_and_score] =
        values = row |> Evision.Mat.to_nx() |> Nx.to_flat_list()

      confidence = List.last(values)

      embedding =
        recognizer
        |> Evision.FaceRecognizerSF.alignCrop(img, row)
        |> then(&Evision.FaceRecognizerSF.feature(recognizer, &1))
        |> Evision.Mat.to_nx()
        |> Nx.to_flat_list()

      %{bbox: {x, y, w, h}, confidence: confidence, embedding: embedding}
    end
  end

  defp ensure_recognizer(%{recognizer: recognizer} = state) when not is_nil(recognizer) do
    {:ok, state}
  end

  defp ensure_recognizer(state) do
    with {:ok, path} <- model_path(@sface_model) do
      {:ok, %{state | recognizer: Evision.FaceRecognizerSF.create(path, "")}}
    end
  end

  defp ensure_detector(%{detector: detector, input_size: size} = state, size)
       when not is_nil(detector) do
    {:ok, state}
  end

  defp ensure_detector(%{detector: detector} = state, {w, h} = size) when not is_nil(detector) do
    Evision.FaceDetectorYN.setInputSize(detector, {w, h})
    {:ok, %{state | input_size: size}}
  end

  # OpenCV's own default `score_threshold` (0.9) is tuned for clean,
  # well-lit, front-facing photos — real wedding/event footage has small
  # distant guests and close-up handheld shots that score well below
  # that and were being silently dropped. Verified against real footage
  # (a background wedding-entrance shot with distant guests, and a close
  # -up baby video) that 0.5 recovers genuine faces without picking up
  # obvious noise from faceless frames.
  @score_threshold 0.5

  defp ensure_detector(state, {w, h} = size) do
    with {:ok, path} <- model_path(@yunet_model) do
      detector =
        Evision.FaceDetectorYN.create(path, "", {w, h}, score_threshold: @score_threshold)

      {:ok, %{state | detector: detector, input_size: size}}
    end
  end

  defp model_path(relative_path) do
    path = Application.app_dir(:phoenix_hologram, relative_path)

    if File.regular?(path) do
      {:ok, path}
    else
      {:error, :models_not_found}
    end
  end
end
