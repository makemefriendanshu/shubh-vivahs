defmodule ShubhVivahs.FaceDetection.SceneIndexTest do
  use ExUnit.Case, async: true

  alias ShubhVivahs.FaceDetection.SceneIndex

  describe "ranges/2" do
    test "returns an empty list for no detections" do
      assert SceneIndex.ranges([]) == []
    end

    test "a single detection is its own single-instant scene" do
      detection = %{frame_time_ms: 5_000}

      assert [%{start_ms: 5_000, end_ms: 5_000, detections: [^detection]}] =
               SceneIndex.ranges([detection])
    end

    test "merges detections within the gap threshold into one scene" do
      detections = [
        %{frame_time_ms: 0},
        %{frame_time_ms: 1_000},
        %{frame_time_ms: 2_000}
      ]

      assert [%{start_ms: 0, end_ms: 2_000, detections: ^detections}] =
               SceneIndex.ranges(detections)
    end

    test "splits into separate scenes once the gap exceeds the threshold" do
      detections = [
        %{frame_time_ms: 0},
        %{frame_time_ms: 1_000},
        %{frame_time_ms: 10_000},
        %{frame_time_ms: 11_000}
      ]

      assert [
               %{start_ms: 0, end_ms: 1_000},
               %{start_ms: 10_000, end_ms: 11_000}
             ] = SceneIndex.ranges(detections)
    end

    test "accepts unsorted detections and returns scenes in chronological order" do
      detections = [
        %{frame_time_ms: 11_000},
        %{frame_time_ms: 0},
        %{frame_time_ms: 10_000},
        %{frame_time_ms: 1_000}
      ]

      assert [
               %{start_ms: 0, end_ms: 1_000},
               %{start_ms: 10_000, end_ms: 11_000}
             ] = SceneIndex.ranges(detections)
    end

    test ":max_gap_ms is configurable" do
      detections = [%{frame_time_ms: 0}, %{frame_time_ms: 3_000}]

      assert [%{start_ms: 0, end_ms: 3_000}] = SceneIndex.ranges(detections, max_gap_ms: 3_000)
      assert [%{start_ms: 0}, %{start_ms: 3_000}] = SceneIndex.ranges(detections, max_gap_ms: 999)
    end
  end

  describe "scenes/2" do
    test "returns an empty list for no detections" do
      assert SceneIndex.scenes([]) == []
    end

    test "one scene while the same set of faces stays on screen" do
      detections = [
        %{frame_time_ms: 0, face_id: 1},
        %{frame_time_ms: 0, face_id: 2},
        %{frame_time_ms: 1_000, face_id: 1},
        %{frame_time_ms: 1_000, face_id: 2},
        %{frame_time_ms: 2_000, face_id: 2},
        %{frame_time_ms: 2_000, face_id: 1}
      ]

      assert [%{start_ms: 0, end_ms: 2_000, face_ids: [1, 2]}] = SceneIndex.scenes(detections)
    end

    test "a new scene starts the moment who's on screen changes" do
      detections = [
        %{frame_time_ms: 0, face_id: 1},
        %{frame_time_ms: 1_000, face_id: 1},
        %{frame_time_ms: 2_000, face_id: 1},
        %{frame_time_ms: 2_000, face_id: 2},
        %{frame_time_ms: 3_000, face_id: 1},
        %{frame_time_ms: 3_000, face_id: 2}
      ]

      assert [
               %{start_ms: 0, end_ms: 1_000, face_ids: [1]},
               %{start_ms: 2_000, end_ms: 3_000, face_ids: [1, 2]}
             ] = SceneIndex.scenes(detections)
    end

    test "the same composition recurring later is a separate scene, not merged" do
      detections = [
        %{frame_time_ms: 0, face_id: 1},
        %{frame_time_ms: 1_000, face_id: 1},
        %{frame_time_ms: 1_000, face_id: 2},
        %{frame_time_ms: 2_000, face_id: 1}
      ]

      assert [
               %{start_ms: 0, end_ms: 0, face_ids: [1]},
               %{start_ms: 1_000, end_ms: 1_000, face_ids: [1, 2]},
               %{start_ms: 2_000, end_ms: 2_000, face_ids: [1]}
             ] = SceneIndex.scenes(detections)
    end

    test "tolerates a missed frame within :max_gap_ms without starting a new scene" do
      detections = [
        %{frame_time_ms: 0, face_id: 1},
        %{frame_time_ms: 3_000, face_id: 1}
      ]

      assert [%{start_ms: 0, end_ms: 3_000, face_ids: [1]}] =
               SceneIndex.scenes(detections, max_gap_ms: 3_000)
    end
  end
end
