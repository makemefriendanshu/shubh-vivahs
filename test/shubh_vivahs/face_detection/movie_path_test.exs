defmodule ShubhVivahs.FaceDetection.MoviePathTest do
  use ShubhVivahs.DataCase, async: true

  alias ShubhVivahs.FaceDetection.{Movie, MoviePath}
  alias ShubhVivahs.Repo

  test "stores paths inside the uploads folder relative to it" do
    absolute = Path.join(MoviePath.uploads_dir(), "4-Someone/000001-Clip.mp4")

    assert MoviePath.dump(absolute) == {:ok, "4-Someone/000001-Clip.mp4"}
    assert MoviePath.load("4-Someone/000001-Clip.mp4") == {:ok, absolute}
  end

  test "leaves paths outside the uploads folder absolute" do
    assert MoviePath.dump("/srv/seed/demo.mp4") == {:ok, "/srv/seed/demo.mp4"}
    assert MoviePath.load("/srv/seed/demo.mp4") == {:ok, "/srv/seed/demo.mp4"}
  end

  test "round-trips through the database and still matches get_by" do
    absolute = Path.join(MoviePath.uploads_dir(), "9-Someone/000002-Clip.mp4")
    movie = Repo.insert!(%Movie{path: absolute, title: "Clip"})

    assert %{rows: [["9-Someone/000002-Clip.mp4"]]} =
             Repo.query!("SELECT path FROM movies WHERE id = ?", [movie.id])

    assert Repo.get!(Movie, movie.id).path == absolute
    assert Repo.get_by(Movie, path: absolute).id == movie.id
  end
end
