defmodule ShubhVivahs.Library do
  @moduledoc """
  General media library — TV series, movies, and songs — separate from the
  wedding films in `ShubhVivahs.FaceDetection`. Items are added with
  `mix library.import` (see `ShubhVivahs.Library.Importer`), which stores
  a browser-playable copy under `storage_dir/0`, and are only ever shown
  to signed-in users (`/library`).

  Every series episode and movie also gets a private backing `Movie`
  (`ensure_movie/1`), so it plays in PlayerPage with the same face
  detection, focus voting, comments, likes, and views as a wedding film.
  `FaceDetection`'s listings leave these movies out, so they never show up
  in Premiere Hall, Dashboard, or the admin film lists. Face detection
  itself is slow, so it runs separately via `mix library.detect_faces` (or
  the admin page's button) rather than during import, and samples a frame
  every 2s (`detect_fps/0`) instead of wedding films' every 1s.
  """

  import Ecto.Query

  alias ShubhVivahs.FaceDetection
  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.Library.MediaItem
  alias ShubhVivahs.MovieThumbnail
  alias ShubhVivahs.Repo

  @video_kinds ~w(series movie)

  # One frame every 2s: halves detection time on hours of TV, and TV shots
  # rarely change who's on screen faster than that. Still within
  # SceneIndex's 2.5s gap tolerance, so consecutive samples merge into
  # scenes the same way 1fps ones do.
  @detect_fps 0.5

  @doc "Frames per second sampled when detecting faces in library videos."
  def detect_fps, do: @detect_fps

  @doc "Folder every imported file, subtitle, and thumbnail lives under."
  @spec storage_dir() :: String.t()
  def storage_dir, do: Path.join(:code.priv_dir(:shubh_vivahs), "library")

  @doc "Absolute path of an item's playable file, or nil if it isn't imported yet."
  def media_path(%MediaItem{path: nil}), do: nil
  def media_path(%MediaItem{path: path}), do: Path.join(storage_dir(), path)

  @doc """
  Where an item's playable file belongs, relative to `storage_dir/0`,
  grouped into readable folders:

      media/series/Game of Thrones/Season 1/S01E01 - Winter Is Coming.mp4
      media/movie/EPiC Elvis Presley In Concert (2025)/EPiC Elvis Presley In Concert (2025).mp4
      media/song/Kishore Kumar/Pal Pal Dil Ke Paas.mp3

  Subtitles sit next to the file with a .vtt extension. If another item
  already owns the same path (two files with the same title), the item's
  id is appended so neither overwrites the other.
  """
  def relative_media_path(%MediaItem{} = item, ext) do
    candidate = Path.join(folder_segments(item) ++ [safe_name(file_stem(item)) <> ext])

    taken? =
      Repo.exists?(from i in MediaItem, where: i.path == ^candidate and i.id != ^(item.id || 0))

    if taken?, do: String.replace_suffix(candidate, ext, " [#{item.id}]" <> ext), else: candidate
  end

  defp folder_segments(%MediaItem{kind: "series"} = item) do
    season = if item.season, do: "Season #{item.season}", else: "Episodes"
    ["media", "series", safe_name(item.collection || "Untitled series"), season]
  end

  defp folder_segments(%MediaItem{kind: "movie"} = item),
    do: ["media", "movie", safe_name(item.title)]

  defp folder_segments(%MediaItem{kind: "song"} = item),
    do: ["media", "song", safe_name(item.collection || "Unknown artist")]

  defp file_stem(%MediaItem{kind: "series", season: s, episode: e, title: title})
       when is_integer(s) and is_integer(e),
       do: "S#{pad2(s)}E#{pad2(e)} - #{title}"

  defp file_stem(%MediaItem{title: title}), do: title

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  # Keeps names readable (spaces, apostrophes, commas, parentheses) but
  # drops characters that are path separators or trouble on other
  # filesystems if the library is ever copied off this machine.
  defp safe_name(name) do
    name
    |> String.replace(":", " -")
    |> String.replace(~r{[/\\*?"<>|\x00-\x1f]}, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.trim_trailing(".")
    |> case do
      "" -> "Untitled"
      safe -> safe
    end
  end

  @doc """
  Moves an item's file (and subtitles) to `relative_media_path/2`,
  updating its row and its backing movie's path together — the file is
  moved back if the database update fails. Returns `{:ok, :moved, item}`,
  `{:ok, :unchanged, item}`, or `{:error, reason}`.
  """
  def reorganize(%MediaItem{path: old_relative} = item) when is_binary(old_relative) do
    new_relative = relative_media_path(item, Path.extname(old_relative))

    if new_relative == old_relative do
      {:ok, :unchanged, item}
    else
      move_item(item, old_relative, new_relative)
    end
  end

  def reorganize(item), do: {:ok, :unchanged, item}

  defp move_item(item, old_relative, new_relative) do
    old_abs = Path.join(storage_dir(), old_relative)
    new_abs = Path.join(storage_dir(), new_relative)
    old_vtt = Path.rootname(old_abs) <> ".vtt"
    new_vtt = Path.rootname(new_abs) <> ".vtt"

    with true <- File.regular?(old_abs) || {:error, {:missing, old_abs}},
         false <- File.exists?(new_abs) && {:error, {:destination_exists, new_abs}},
         :ok <- File.mkdir_p(Path.dirname(new_abs)),
         :ok <- File.rename(old_abs, new_abs) do
      if File.regular?(old_vtt), do: File.rename!(old_vtt, new_vtt)
      extra_audio = item |> audio_versions() |> Enum.drop(1) |> Enum.map(& &1.language)

      for code <- extra_audio, File.regular?(alternate_audio_path(old_abs, code)) do
        File.rename!(alternate_audio_path(old_abs, code), alternate_audio_path(new_abs, code))
      end

      Repo.transaction(fn ->
        item = item |> MediaItem.changeset(%{path: new_relative}) |> Repo.update!()

        if movie = item.movie_id && Repo.get(Movie, item.movie_id) do
          movie |> Movie.changeset(%{path: new_abs}) |> Repo.update!()
        end

        item
      end)
      |> case do
        {:ok, item} ->
          remove_empty_dirs(Path.dirname(old_abs))
          {:ok, :moved, item}

        {:error, reason} ->
          File.rename(new_abs, old_abs)
          if File.regular?(new_vtt), do: File.rename(new_vtt, old_vtt)

          for code <- extra_audio, File.regular?(alternate_audio_path(new_abs, code)) do
            File.rename(alternate_audio_path(new_abs, code), alternate_audio_path(old_abs, code))
          end

          {:error, reason}
      end
    end
  end

  # Tidies folders a move left empty, up to (not including) media/<kind>.
  defp remove_empty_dirs(dir) do
    stop = Path.join(storage_dir(), "media")

    if String.starts_with?(dir, stop <> "/") and Path.dirname(dir) != stop and
         File.ls(dir) == {:ok, []} do
      File.rmdir(dir)
      remove_empty_dirs(Path.dirname(dir))
    end
  end

  @language_names %{
    "eng" => "English",
    "hin" => "Hindi",
    "tam" => "Tamil",
    "tel" => "Telugu",
    "spa" => "Spanish",
    "mal" => "Malayalam",
    "kan" => "Kannada",
    "ben" => "Bengali",
    "mar" => "Marathi",
    "urd" => "Urdu",
    "fre" => "French",
    "ger" => "German",
    "jpn" => "Japanese",
    "kor" => "Korean"
  }

  @doc "A readable name for an ISO 639-2 audio language code."
  def language_name(code), do: Map.get(@language_names, code, String.upcase(code))

  @doc """
  The item's audio versions, main file first, as
  `[%{language: "eng", name: "English", path: absolute_path}, ...]` —
  each extra language is a full copy next to the main file, named
  `<main file>.<code>.mp4`. A single entry (language nil) for items
  imported with one track.
  """
  def audio_versions(%MediaItem{path: nil}), do: []

  def audio_versions(%MediaItem{audio_languages: languages} = item)
      when is_binary(languages) and languages != "" do
    [main | extra] = String.split(languages, ",")
    main_path = media_path(item)

    [%{language: main, name: language_name(main), path: main_path}] ++
      Enum.map(extra, fn code ->
        %{language: code, name: language_name(code), path: alternate_audio_path(main_path, code)}
      end)
  end

  def audio_versions(item), do: [%{language: nil, name: nil, path: media_path(item)}]

  @doc "Where the copy of a file with `code` audio lives, next to it."
  def alternate_audio_path(main_path, code), do: Path.rootname(main_path) <> ".#{code}.mp4"

  @doc "Absolute path of an item's WebVTT subtitles, or nil if it has none."
  def subtitle_path(%MediaItem{has_subtitles: true, path: path}) when is_binary(path),
    do: Path.join(storage_dir(), Path.rootname(path) <> ".vtt")

  def subtitle_path(_item), do: nil

  @doc "Path an item's poster thumbnail would live at, whether or not it exists."
  def thumbnail_path(%MediaItem{id: id}),
    do: Path.join([storage_dir(), "thumbnails", "#{id}.jpg"])

  def get_item(id), do: Repo.get(MediaItem, id)

  @doc "The library item a backing movie belongs to, or nil for a wedding film."
  def get_by_movie_id(movie_id), do: Repo.get_by(MediaItem, movie_id: movie_id)

  @doc """
  Links a ready video item to a private backing `Movie` (status
  "pending" until `detect_faces/1` runs), creating it if needed, and
  seeds its poster with the library thumbnail — MovieThumbnail's default
  frame 5s in is usually a studio logo. A no-op returning `{:ok, item}`
  for songs, unfinished imports, and items already linked.
  """
  def ensure_movie(%MediaItem{movie_id: nil, status: "ready", kind: kind} = item)
      when kind in @video_kinds do
    path = media_path(item)

    Repo.transaction(fn ->
      movie =
        Repo.get_by(Movie, path: path) ||
          %Movie{}
          |> Movie.changeset(%{
            path: path,
            title: movie_title(item),
            status: "pending",
            public: false,
            # Copied in directly, not uploaded through the site: credit the
            # site owner (shows in its URL, /premiere/<uploader>/<slug>) —
            # if that account exists, else leave it uncredited.
            user_id: owner_user_id()
          })
          |> Repo.insert!()

      seed_thumbnail(item, movie)
      item |> MediaItem.changeset(%{movie_id: movie.id}) |> Repo.update!()
    end)
  end

  def ensure_movie(item), do: {:ok, item}

  @doc """
  Runs face detection on `item`'s backing movie (see
  `FaceDetection.ingest_video/2`), which reuses that movie row by path.
  Returns `{:ok, movie}` or `{:error, reason}`.
  """
  def detect_faces(%MediaItem{} = item) do
    with {:ok, item} <- ensure_movie(item),
         %MediaItem{movie_id: movie_id} when not is_nil(movie_id) <- item do
      FaceDetection.ingest_video(media_path(item), title: movie_title(item), fps: @detect_fps)
    else
      %MediaItem{} -> {:error, :not_a_video}
      error -> error
    end
  end

  @doc "Every ready series episode and movie, in display order."
  def list_ready_videos, do: Enum.flat_map(@video_kinds, &list_ready/1)

  @doc ~s(Title for the backing movie, e.g. "Game of Thrones S01E01 · Winter Is Coming".)
  def movie_title(%MediaItem{kind: "series", season: s, episode: e} = item)
      when is_integer(s) and is_integer(e) do
    code = "S#{String.pad_leading("#{s}", 2, "0")}E#{String.pad_leading("#{e}", 2, "0")}"
    "#{item.collection} #{code} · #{item.title}"
  end

  def movie_title(%MediaItem{collection: nil, title: title}), do: title

  def movie_title(%MediaItem{collection: collection, title: title}),
    do: "#{collection} · #{title}"

  defp owner_user_id do
    id = FaceDetection.owner_user_id()
    if Repo.get(ShubhVivahs.Accounts.User, id), do: id
  end

  defp seed_thumbnail(item, movie) do
    source = thumbnail_path(item)
    dest = MovieThumbnail.thumbnail_path(movie)

    if File.regular?(source) and not File.regular?(dest) do
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(source, dest)
    end
  end

  @doc """
  Every ready item of `kind`, ordered for display: episodes by series,
  season, episode; songs by artist then title; movies by title.
  """
  def list_ready(kind) do
    Repo.all(
      from i in MediaItem,
        where: i.kind == ^kind and i.status == "ready",
        order_by: [asc: i.collection, asc: i.season, asc: i.episode, asc: i.title, asc: i.id]
    )
  end

  @doc """
  The episodes either side of `item` in its series (across seasons), as
  `{previous, next}` — either may be nil. Always `{nil, nil}` for
  anything that isn't an episode.
  """
  def neighbours(%MediaItem{kind: "series", collection: collection} = item) do
    episodes =
      "series"
      |> list_ready()
      |> Enum.filter(&(&1.collection == collection))

    index = Enum.find_index(episodes, &(&1.id == item.id))

    if index do
      previous = if index > 0, do: Enum.at(episodes, index - 1)
      {previous, Enum.at(episodes, index + 1)}
    else
      {nil, nil}
    end
  end

  def neighbours(_item), do: {nil, nil}
end
