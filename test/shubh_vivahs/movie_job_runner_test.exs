defmodule ShubhVivahs.MovieJobRunnerTest do
  use ShubhVivahs.DataCase, async: true

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.MovieJobRunner
  alias ShubhVivahs.MovieJobs
  alias ShubhVivahs.MovieJobs.MovieJob
  alias ShubhVivahs.Repo

  test "refuses a movie that doesn't exist" do
    assert MovieJobRunner.start(-1, "recognition") == {:error, :not_found}
    assert MovieJobRunner.start(-1, "versions") == {:error, :not_found}
  end

  test "refuses recognition for a movie that's already being scanned" do
    movie = Repo.insert!(%Movie{path: "/nonexistent/busy.mp4", status: "processing"})

    assert MovieJobRunner.start(movie.id, "recognition") == {:error, :already_running}
    assert Repo.get!(Movie, movie.id).status == "processing"
  end

  test "refuses versions while that job is running" do
    movie = Repo.insert!(%Movie{path: "/nonexistent/busy.mp4"})
    MovieJobs.start(movie.id, "versions")

    assert MovieJobRunner.start(movie.id, "versions") == {:error, :already_running}
  end

  describe "MovieJobs" do
    test "a running job that hasn't reported for over 10 minutes is stalled" do
      movie = Repo.insert!(%Movie{path: "/nonexistent/stalled.mp4"})
      MovieJobs.start(movie.id, "recognition")
      job = MovieJobs.get(movie.id, "recognition")

      refute MovieJobs.stalled?(job)

      assert MovieJobs.stalled?(%MovieJob{
               job
               | updated_at: DateTime.add(job.updated_at, -11, :minute)
             })

      refute MovieJobs.stalled?(%MovieJob{job | status: "done"})
    end

    test "reporter records stage and progress, and estimates time left" do
      movie = Repo.insert!(%Movie{path: "/nonexistent/progress.mp4"})
      MovieJobs.start(movie.id, "versions")
      report = MovieJobs.reporter(movie.id, "versions")

      report.("Making 360p minimal version", 0.5)
      job = MovieJobs.get(movie.id, "versions")
      assert %{stage: "Making 360p minimal version", progress: 0.5, status: "running"} = job

      started = DateTime.add(DateTime.utc_now(), -60, :second)
      assert MovieJobs.seconds_left(%MovieJob{job | started_at: started}) in 59..61

      MovieJobs.finish(movie.id, "versions")
      assert %{status: "done", progress: 1.0} = MovieJobs.get(movie.id, "versions")
    end
  end
end
