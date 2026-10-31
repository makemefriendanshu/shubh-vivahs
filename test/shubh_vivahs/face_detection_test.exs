defmodule ShubhVivahs.FaceDetectionTest do
  use ShubhVivahs.DataCase, async: true

  alias ShubhVivahs.FaceDetection
  alias ShubhVivahs.FaceDetection.{Face, Movie}
  alias ShubhVivahs.FaceThumbnail

  describe "Movie.changeset/2" do
    test "requires a path" do
      refute Movie.changeset(%Movie{}, %{}).valid?
      assert Movie.changeset(%Movie{}, %{path: "video.mp4"}).valid?
    end
  end

  describe "Face embedding round-trip" do
    test "a face's embedding survives insert + reload" do
      {:ok, movie} = %Movie{} |> Movie.changeset(%{path: "video.mp4"}) |> Repo.insert()
      embedding = [0.5, -1.25, 0.0, 3.0625]

      {:ok, face} =
        %Face{} |> Face.changeset(%{movie_id: movie.id, embedding: embedding}) |> Repo.insert()

      reloaded = Repo.get!(Face, face.id)

      for {expected, actual} <- Enum.zip(embedding, reloaded.embedding) do
        assert_in_delta expected, actual, 1.0e-6
      end
    end
  end

  # Full ingest -> detect -> cluster -> persist pipeline, run against a
  # real local video. Needs `mix face_detection.setup` (models + ffmpeg)
  # and a real video path in FACE_DETECTION_TEST_VIDEO — not something
  # CI/a fresh checkout can provide, so this stays excluded by default
  # (see test/test_helper.exs) and is meant to be run locally:
  #
  #     FACE_DETECTION_TEST_VIDEO=path/to/clip.mp4 mix test --include face_detection_models
  describe "ingest_video/2" do
    @tag :face_detection_models
    test "detects and clusters faces from a real video" do
      video_path =
        System.get_env("FACE_DETECTION_TEST_VIDEO") ||
          flunk("set FACE_DETECTION_TEST_VIDEO to a local video path to run this test")

      assert {:ok, movie} = FaceDetection.ingest_video(video_path)
      assert movie.status == "done"
      assert is_list(movie.faces)

      for face <- movie.faces do
        assert is_list(face.embedding)
        assert face.detections != []
      end

      [first_face | _] = movie.faces
      face_with_movie = %{first_face | movie: movie}
      thumbnail_path = FaceThumbnail.generate!(face_with_movie)
      assert File.regular?(thumbnail_path)
      assert FaceThumbnail.thumbnail_ready?(face_with_movie)

      assert {:ok, reingested_movie} = FaceDetection.ingest_video(video_path)
      assert reingested_movie.id == movie.id
      assert Repo.aggregate(Movie, :count, :id) == 1
      assert Enum.map(reingested_movie.faces, & &1.id) != Enum.map(movie.faces, & &1.id)
    end
  end
end
