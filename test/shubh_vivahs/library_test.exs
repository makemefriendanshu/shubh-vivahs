defmodule ShubhVivahs.LibraryTest do
  use ShubhVivahs.DataCase, async: true

  alias ShubhVivahs.Library
  alias ShubhVivahs.Library.MediaItem
  alias ShubhVivahs.Repo

  defp episode!(season, episode, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %MediaItem{
          kind: "series",
          collection: "Show",
          season: season,
          episode: episode,
          title: "S#{season}E#{episode}",
          source_path: "/src/Show/S#{season}E#{episode}.mkv",
          status: "ready"
        },
        attrs
      )
    )
  end

  test "list_ready/1 orders episodes by season then episode and skips unfinished imports" do
    e2_1 = episode!(2, 1)
    e1_2 = episode!(1, 2)
    e1_1 = episode!(1, 1)
    _failed = episode!(1, 3, %{status: "failed"})

    assert Enum.map(Library.list_ready("series"), & &1.id) == [e1_1.id, e1_2.id, e2_1.id]
  end

  test "neighbours/1 crosses season boundaries and stays within the series" do
    e1_1 = episode!(1, 1)
    e1_2 = episode!(1, 2)
    e2_1 = episode!(2, 1)
    _other = episode!(1, 3, %{collection: "Other Show", source_path: "/src/Other/S1E3.mkv"})

    assert Library.neighbours(e1_1) == {nil, e1_2}
    assert Library.neighbours(e1_2) == {e1_1, e2_1}
    assert Library.neighbours(e2_1) == {e1_2, nil}
  end

  describe "ensure_movie/1" do
    test "links a private backing movie once, hidden from wedding listings" do
      item = episode!(1, 1, %{path: "media/series/000001-Show.mp4"})

      {:ok, linked} = Library.ensure_movie(item)
      movie = Repo.get!(ShubhVivahs.FaceDetection.Movie, linked.movie_id)

      assert movie.path == Library.media_path(item)
      assert movie.title == "Show S01E01 · S1E1"
      refute movie.public
      assert {:ok, %{movie_id: same_id}} = Library.ensure_movie(linked)
      assert same_id == movie.id

      assert ShubhVivahs.FaceDetection.library_movie?(movie)
      refute movie.id in Enum.map(ShubhVivahs.FaceDetection.list_movies_ordered(), & &1.id)
    end

    test "credits the site owner as uploader when that account exists" do
      Repo.insert!(%ShubhVivahs.Accounts.User{
        id: ShubhVivahs.FaceDetection.owner_user_id(),
        name: "Anshuman",
        email: "owner-#{System.unique_integer([:positive])}@example.com",
        hashed_password: "x"
      })

      item =
        episode!(3, 1, %{path: "media/series/owner-test.mp4", source_path: "/src/owner-test.mkv"})

      {:ok, linked} = Library.ensure_movie(item)

      movie = Repo.get!(ShubhVivahs.FaceDetection.Movie, linked.movie_id)
      assert movie.user_id == ShubhVivahs.FaceDetection.owner_user_id()
      assert ShubhVivahs.MovieSlug.path(movie) == "/library/anshuman/show-s03e01-s3e1"
    end

    test "leaves songs unlinked" do
      song =
        Repo.insert!(%MediaItem{
          kind: "song",
          title: "Tune",
          path: "media/song/000001-Tune.mp3",
          source_path: "/src/Tune.mp3",
          status: "ready"
        })

      assert {:ok, %{movie_id: nil}} = Library.ensure_movie(song)
    end
  end

  describe "relative_media_path/2 and reorganize/1" do
    test "groups episodes by series and season, movies by title" do
      episode = %MediaItem{
        id: 1,
        kind: "series",
        collection: "Game of Thrones",
        season: 1,
        episode: 3,
        title: "Lord Snow"
      }

      movie = %MediaItem{id: 2, kind: "movie", title: "Another World: The Making Of (1991)"}

      assert Library.relative_media_path(episode, ".mp4") ==
               "media/series/Game of Thrones/Season 1/S01E03 - Lord Snow.mp4"

      assert Library.relative_media_path(movie, ".mp4") ==
               "media/movie/Another World - The Making Of (1991)/Another World - The Making Of (1991).mp4"
    end

    test "moves the file and subtitles and updates the item and its backing movie" do
      old = "media/series/test-#{System.unique_integer([:positive])}-flat.mp4"
      old_abs = Path.join(Library.storage_dir(), old)
      File.mkdir_p!(Path.dirname(old_abs))
      File.write!(old_abs, "video")
      File.write!(Path.rootname(old_abs) <> ".vtt", "WEBVTT")

      show = "Reorg Test #{System.unique_integer([:positive])}"

      item =
        episode!(2, 4, %{
          collection: show,
          path: old,
          has_subtitles: true,
          source_path: "/src/#{show}.mkv"
        })

      {:ok, item} = Library.ensure_movie(item)

      assert {:ok, :moved, moved} = Library.reorganize(item)
      new_abs = Library.media_path(moved)
      on_exit(fn -> File.rm_rf!(Path.join([Library.storage_dir(), "media/series", show])) end)

      assert moved.path == "media/series/#{show}/Season 2/S02E04 - S2E4.mp4"
      assert File.read!(new_abs) == "video"
      assert File.read!(Library.subtitle_path(moved)) == "WEBVTT"
      refute File.exists?(old_abs)
      assert Repo.get!(ShubhVivahs.FaceDetection.Movie, moved.movie_id).path == new_abs
      assert {:ok, :unchanged, _} = Library.reorganize(moved)
    end
  end

  test "audio_versions/1 lists the main file then each extra language copy" do
    item = %MediaItem{
      path: "media/series/Show/Season 1/S01E01 - Pilot.mp4",
      audio_languages: "eng,hin"
    }

    main = Library.media_path(item)

    assert [
             %{language: "eng", name: "English", path: ^main},
             %{language: "hin", name: "Hindi", path: hindi}
           ] = Library.audio_versions(item)

    assert hindi == String.replace_suffix(main, ".mp4", ".hin.mp4")
    assert [%{language: nil}] = Library.audio_versions(%MediaItem{path: "media/movie/x.mp4"})
  end
end
