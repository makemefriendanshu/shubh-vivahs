defmodule ShubhVivahs.FaceDetection.SceneIndex do
  @moduledoc """
  Collapses raw per-frame detections (one row per sampled frame a face
  was seen in) into contiguous timestamp ranges.

  Two related groupings:

    * `ranges/2` — one face's own appearances over time, ignoring
      everyone else on screen.
    * `scenes/2` — the movie's actual scene timeline: a scene is a
      stretch where the *set* of faces on screen doesn't change: a new
      scene starts the instant someone enters or leaves shot.

  Both merge consecutive sampled frames as long as the gap between them
  is within `:max_gap_ms` (default 2.5s), to tolerate the odd missed
  frame at the default 1fps sampling rate without splitting one
  continuous appearance/composition into several.
  """

  @default_max_gap_ms 2_500

  @doc """
  Returns one face's own appearances as
  `%{start_ms: ms, end_ms: ms, detections: [detection, ...]}`, in
  chronological order. Each `detection` must have a `:frame_time_ms`.
  This says nothing about who *else* was on screen at the same time —
  see `scenes/2` for that.
  """
  def ranges(detections, opts \\ [])
  def ranges([], _opts), do: []

  def ranges(detections, opts) do
    max_gap_ms = Keyword.get(opts, :max_gap_ms, @default_max_gap_ms)

    detections
    |> Enum.sort_by(& &1.frame_time_ms)
    |> Enum.reduce([], fn detection, scenes -> add(scenes, detection, max_gap_ms) end)
    |> Enum.reverse()
    |> Enum.map(fn scene -> %{scene | detections: Enum.reverse(scene.detections)} end)
  end

  defp add(
         [%{end_ms: end_ms, detections: detections} = current | rest],
         detection,
         max_gap_ms
       )
       when detection.frame_time_ms - end_ms <= max_gap_ms do
    [%{current | end_ms: detection.frame_time_ms, detections: [detection | detections]} | rest]
  end

  defp add(scenes, detection, _max_gap_ms) do
    [
      %{
        start_ms: detection.frame_time_ms,
        end_ms: detection.frame_time_ms,
        detections: [detection]
      }
      | scenes
    ]
  end

  @doc """
  Segments **all** of a movie's detections (across every face) into
  scenes: contiguous stretches of sampled frames where the same set of
  faces is on screen together. A scene ends the moment that set
  changes — someone enters or leaves shot — or the gap since the last
  sampled frame exceeds `:max_gap_ms`.

  Each `detection` must have `:frame_time_ms` and `:face_id`. Returns
  `%{start_ms: ms, end_ms: ms, face_ids: [id, ...]}` (face_ids sorted
  and deduplicated) in chronological order.
  """
  def scenes(detections, opts \\ [])
  def scenes([], _opts), do: []

  def scenes(detections, opts) do
    max_gap_ms = Keyword.get(opts, :max_gap_ms, @default_max_gap_ms)

    detections
    |> Enum.group_by(& &1.frame_time_ms, & &1.face_id)
    |> Enum.map(fn {frame_time_ms, face_ids} ->
      {frame_time_ms, face_ids |> Enum.uniq() |> Enum.sort()}
    end)
    |> Enum.sort_by(fn {frame_time_ms, _face_ids} -> frame_time_ms end)
    |> Enum.reduce([], fn frame, scenes -> add_scene(scenes, frame, max_gap_ms) end)
    |> Enum.reverse()
  end

  defp add_scene(
         [%{end_ms: end_ms, face_ids: face_ids} = current | rest],
         {frame_time_ms, face_ids},
         max_gap_ms
       )
       when frame_time_ms - end_ms <= max_gap_ms do
    [%{current | end_ms: frame_time_ms} | rest]
  end

  defp add_scene(scenes, {frame_time_ms, face_ids}, _max_gap_ms) do
    [%{start_ms: frame_time_ms, end_ms: frame_time_ms, face_ids: face_ids} | scenes]
  end
end
