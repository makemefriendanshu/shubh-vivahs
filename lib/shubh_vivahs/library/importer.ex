defmodule ShubhVivahs.Library.Importer do
  @moduledoc """
  Adds files to the media library (see `ShubhVivahs.Library`).

  Videos are remuxed into a faststart MP4 so every browser can play them
  and start before the whole file arrives: H.264 video and AAC audio are
  stream-copied (seconds, not minutes), anything else is transcoded
  (e.g. AC3/DTS audio, which no browser plays, becomes stereo AAC).
  English text subtitles — a sidecar `.srt`/`.vtt` next to the file or in
  a `Subs/` folder beside it, or an embedded English (else untagged)
  track — are converted to WebVTT. Video that has to be re-encoded is
  capped at 720p. Songs are copied as-is,
  since every format accepted here already plays in browsers.

  Titles, series names, season/episode numbers, and artists are parsed
  from file and folder names (`describe/3`) — release-group tags like
  "1080p BluRay x264" are dropped.
  """

  alias ShubhVivahs.FaceDetection.FrameExtractor
  alias ShubhVivahs.Library
  alias ShubhVivahs.Library.MediaItem
  alias ShubhVivahs.Repo

  @video_extensions ~w(.mkv .mp4 .m4v .mov .webm .avi)
  @audio_extensions ~w(.mp3 .m4a .aac .ogg .opus .flac .wav)
  @text_subtitle_codecs ~w(subrip srt ass ssa mov_text webvtt text)
  @thumbnail_max_width 640

  @release_tag ~r/[\s(\[]*\b(\d{3,4}p|repack|proper|internal|bluray|blu-ray|brrip|bdrip|web-?dl|webrip|hdtv|dvdrip|x264|x265|h\.?264|h\.?265|hevc|aac\d?(\.\d)?|ac3|dts)\b.*$/i
  @episode_code ~r/\bS(\d{1,2})\s*E(\d{1,3})\b(.*)$/i

  @doc "Files under `source` (a file or a folder, searched recursively) that `kind` accepts, sorted."
  @spec importable_files(String.t(), String.t()) :: [String.t()]
  def importable_files(source, kind) do
    extensions = if kind == "song", do: @audio_extensions, else: @video_extensions

    source
    |> Path.expand()
    |> walk()
    |> Enum.filter(&(&1 |> Path.extname() |> String.downcase() |> Kernel.in(extensions)))
    |> Enum.sort()
  end

  defp walk(path) do
    if File.dir?(path) do
      path |> File.ls!() |> Enum.flat_map(&walk(Path.join(path, &1)))
    else
      [path]
    end
  end

  @doc """
  Imports one file as `kind` ("series", "movie", or "song"). Returns
  `{:ok, item}`, `{:skipped, item}` when it was already imported, or
  `{:error, reason}`.

  Options:
    * `:title` - overrides the title parsed from the filename
    * `:collection` - series name / artist, overriding the parsed one
    * `:season`, `:episode` - override the numbers parsed from the filename
    * `:audio` - languages to keep, e.g. `["eng", "hin"]`: the first is the
      main file's audio, each other one gets its own copy (players switch
      between them); without it, the English (else first) track is used
  """
  @spec import_file(String.t(), String.t(), keyword) ::
          {:ok, MediaItem.t()} | {:skipped, MediaItem.t()} | {:error, term}
  def import_file(source, kind, opts \\ []) do
    source = Path.expand(source)

    case Repo.get_by(MediaItem, source_path: source) do
      %MediaItem{status: "ready"} = item ->
        # Still links items imported before backing movies existed.
        {:ok, item} = Library.ensure_movie(item)
        {:skipped, item}

      existing ->
        attrs =
          source
          |> describe(kind, opts)
          |> Map.merge(%{kind: kind, source_path: source, status: "processing"})

        with {:ok, item} <- (existing || %MediaItem{}) |> MediaItem.changeset(attrs) |> upsert() do
          case process(item, source, opts) do
            {:ok, item} ->
              Library.ensure_movie(item)

            {:error, reason} ->
              item |> MediaItem.changeset(%{status: "failed"}) |> Repo.update()
              {:error, reason}
          end
        end
    end
  end

  defp upsert(%Ecto.Changeset{data: %{id: nil}} = changeset), do: Repo.insert(changeset)
  defp upsert(changeset), do: Repo.update(changeset)

  @doc """
  Title, collection (series name / artist), season, and episode for a
  file, parsed from its name — and, for an episode, its folder's name
  for the series ("Game of Thrones Season 1" -> "Game of Thrones").
  """
  @spec describe(String.t(), String.t(), keyword) :: map
  def describe(path, kind, opts \\ [])

  def describe(path, "series", opts) do
    base = basename(path)
    collection = opts[:collection] || series_name(path |> Path.dirname() |> Path.basename())

    attrs =
      case Regex.run(@episode_code, base) do
        [_, season, episode, rest] ->
          episode = String.to_integer(episode)
          title = clean_title(rest)

          %{
            season: String.to_integer(season),
            episode: episode,
            title: if(title == "", do: "Episode #{episode}", else: title)
          }

        nil ->
          %{season: nil, episode: nil, title: clean_title(base)}
      end

    attrs
    |> Map.put(:collection, collection)
    |> override_episode(opts)
    |> override_title(opts)
  end

  def describe(path, "movie", opts) do
    title =
      case Regex.run(~r/^(.+?)[\s(\[]+((?:19|20)\d{2})[)\]]?$/, clean_title(basename(path))) do
        [_, name, year] -> "#{name} (#{year})"
        nil -> clean_title(basename(path))
      end

    override_title(%{title: title, collection: nil, season: nil, episode: nil}, opts)
  end

  def describe(path, "song", opts) do
    attrs =
      case path |> basename() |> clean_title() |> String.split(" - ", parts: 2) do
        [artist, title] -> %{collection: artist, title: title}
        [title] -> %{collection: nil, title: title}
      end

    attrs
    |> Map.merge(%{season: nil, episode: nil})
    |> Map.update!(:collection, &(opts[:collection] || &1))
    |> override_title(opts)
  end

  # --season/--episode for files whose names do not say (e.g. "EP06").
  defp override_episode(attrs, opts) do
    attrs
    |> then(&if(opts[:season], do: %{&1 | season: opts[:season]}, else: &1))
    |> then(&if(opts[:episode], do: %{&1 | episode: opts[:episode]}, else: &1))
  end

  defp override_title(attrs, opts) do
    case opts[:title] do
      nil -> attrs
      title -> %{attrs | title: title}
    end
  end

  defp basename(path), do: Path.basename(path, Path.extname(path))

  defp series_name(folder) do
    folder
    |> String.replace(~r/[._]+/, " ")
    |> String.replace(~r/\s*\b(season|series|s)\s*\d+\b.*$/i, "")
    |> clean_title()
  end

  defp clean_title(string) do
    string
    |> String.replace(~r/[._]+/, " ")
    |> String.replace(@release_tag, "")
    |> String.trim()
    |> String.trim_leading("-")
    |> String.trim_trailing("-")
    |> String.trim()
  end

  defp process(%MediaItem{kind: "song"} = item, source, _opts) do
    relative = Library.relative_media_path(item, Path.extname(source) |> String.downcase())
    dest = Path.join(Library.storage_dir(), relative)
    File.mkdir_p!(Path.dirname(dest))
    File.cp!(source, dest)

    with {:ok, streams} <- probe(source) do
      # Embedded cover art shows up as a still "video" stream.
      if streams.cover != [] or streams.video != [], do: thumbnail(item, source, 0)

      item |> MediaItem.changeset(%{path: relative, status: "ready"}) |> Repo.update()
    end
  end

  defp process(item, source, opts) do
    relative = Library.relative_media_path(item, ".mp4")
    dest = Path.join(Library.storage_dir(), relative)
    partial = dest <> ".part"
    File.mkdir_p!(Path.dirname(dest))
    [main_language | extra_languages] = opts[:audio] || [nil]

    with {:ok, streams} <- probe(source),
         {:ok, video} <- first_video(streams),
         :ok <-
           ffmpeg(remux_args(source, partial, video, pick_audio(streams.audio, main_language))) do
      File.rename!(partial, dest)
      vtt = Path.rootname(dest) <> ".vtt"
      has_subtitles = subtitles(source, streams, vtt) == :ok
      unless has_subtitles, do: File.rm(vtt)
      thumbnail(item, dest, thumbnail_offset(streams.duration_s))
      extra = alternate_audio(source, dest, video, streams, extra_languages)

      item
      |> MediaItem.changeset(%{
        path: relative,
        status: "ready",
        has_subtitles: has_subtitles,
        audio_languages: audio_languages(streams, main_language, extra)
      })
      |> Repo.update()
    else
      error ->
        File.rm(partial)
        error
    end
  end

  # One full copy per extra audio language (video stream-copied, so it is
  # quick), next to the main file — see Library.audio_versions/1. Languages
  # the file has no track for are skipped. Returns the codes that worked.
  defp alternate_audio(_source, _dest, _video, _streams, []), do: []

  defp alternate_audio(source, dest, video, streams, languages) do
    for code <- languages,
        audio = Enum.find(streams.audio, &(&1.language == code)),
        alt = Library.alternate_audio_path(dest, code),
        :ok == ffmpeg(remux_args(source, alt <> ".part", video, audio)),
        :ok == File.rename(alt <> ".part", alt) do
      code
    end
  end

  # "eng,hin" when there are copies in more than one language, else nil.
  defp audio_languages(_streams, _main, []), do: nil

  defp audio_languages(streams, main, extra) do
    main = main || (preferred(streams.audio) || %{language: "und"}).language
    Enum.join([main | extra], ",")
  end

  # The requested language if the file has it, else the usual preference.
  defp pick_audio(audio, nil), do: preferred(audio)
  defp pick_audio(audio, code), do: Enum.find(audio, &(&1.language == code)) || preferred(audio)

  defp first_video(%{video: [video | _]}), do: {:ok, video}
  defp first_video(_streams), do: {:error, :no_video_stream}

  # English first, then whatever the file marks as default order.
  defp preferred([]), do: nil
  defp preferred(streams), do: Enum.find(streams, hd(streams), &(&1.language == "eng"))

  defp remux_args(source, dest, video, audio) do
    video_codec =
      if video.codec == "h264" and not video.ten_bit?,
        do: ["-c:v", "copy"],
        else: [
          "-c:v",
          "libx264",
          "-preset",
          "veryfast",
          "-crf",
          "22",
          "-pix_fmt",
          "yuv420p",
          # Re-encoding anyway (e.g. HEVC, which browsers don't reliably
          # play), so cap at 720p: far quicker to encode, and light enough
          # to stream over the site's slow uplink.
          "-vf",
          "scale=-2:'min(720,ih)'"
        ]

    {audio_map, audio_codec} =
      cond do
        audio == nil -> {[], []}
        audio.codec == "aac" -> {["-map", "0:#{audio.index}"], ["-c:a", "copy"]}
        true -> {["-map", "0:#{audio.index}"], ["-c:a", "aac", "-b:a", "192k", "-ac", "2"]}
      end

    ["-y", "-i", source, "-map", "0:#{video.index}"] ++
      audio_map ++
      video_codec ++
      audio_codec ++ ["-sn", "-dn", "-movflags", "+faststart", "-f", "mp4", dest]
  end

  defp subtitles(source, streams, vtt) do
    sidecar = find_sidecar(source)

    # Forced tracks only cover foreign-language lines, so skip them;
    # prefer English, then untagged tracks (plenty of rips never set a
    # language), and plain subtitles over hearing-impaired (SDH) ones.
    usable =
      Enum.filter(streams.subtitle, fn stream ->
        stream.codec in @text_subtitle_codecs and not stream.forced?
      end)

    candidates =
      case Enum.filter(usable, &(&1.language == "eng")) do
        [] -> Enum.filter(usable, &(&1.language in [nil, "und"]))
        english -> english
      end

    embedded = Enum.find(candidates, List.first(candidates), &(not &1.hearing_impaired?))

    cond do
      sidecar -> ffmpeg(["-y", "-i", sidecar, "-f", "webvtt", vtt])
      embedded -> ffmpeg(["-y", "-i", source, "-map", "0:#{embedded.index}", "-f", "webvtt", vtt])
      true -> :none
    end
  end

  # Same-named .srt/.vtt next to the file, or in a Subs/ folder beside it
  # (how many season packs ship them).
  defp find_sidecar(source) do
    base = Path.basename(source, Path.extname(source))
    dir = Path.dirname(source)

    for folder <- [dir, Path.join(dir, "Subs"), Path.join(dir, "subs")],
        ext <- [".srt", ".en.srt", ".eng.srt", ".vtt"],
        path = Path.join(folder, base <> ext),
        File.regular?(path),
        reduce: nil do
      nil -> path
      found -> found
    end
  end

  # A tenth of the way in, capped at 5 minutes — far enough to skip
  # studio logos and cold-open black frames.
  defp thumbnail_offset(nil), do: 5
  defp thumbnail_offset(duration_s), do: min(round(duration_s / 10), 300)

  defp thumbnail(item, source, offset) do
    dest = Library.thumbnail_path(item)
    File.mkdir_p!(Path.dirname(dest))

    ffmpeg([
      "-y",
      "-ss",
      "#{offset}",
      "-i",
      source,
      "-map",
      "0:v:0",
      "-frames:v",
      "1",
      "-vf",
      "scale='min(#{@thumbnail_max_width},iw)':-2",
      "-q:v",
      "5",
      dest
    ])
  end

  @stream_line ~r/Stream #0:(\d+)(?:\[\w+\])?(?:\((\w+)\))?: (Video|Audio|Subtitle): (\w+)(.*)$/

  @doc false
  # Parses `ffmpeg -i`'s stream listing — the bundled ffmpeg ships
  # without ffprobe.
  def parse_probe(output) do
    streams =
      output
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case Regex.run(@stream_line, line) do
          [_, index, language, type, codec, rest] ->
            [
              %{
                index: String.to_integer(index),
                language: if(language == "", do: nil, else: language),
                type: type,
                codec: codec,
                ten_bit?: String.contains?(rest, "10le"),
                forced?: String.contains?(rest, "(forced)"),
                hearing_impaired?: String.contains?(rest, "(hearing impaired)"),
                attached_pic?: String.contains?(rest, "attached pic")
              }
            ]

          nil ->
            []
        end
      end)

    by_type = fn type -> Enum.filter(streams, &(&1.type == type)) end

    %{
      video: Enum.reject(by_type.("Video"), & &1.attached_pic?),
      cover: Enum.filter(by_type.("Video"), & &1.attached_pic?),
      audio: by_type.("Audio"),
      subtitle: by_type.("Subtitle"),
      duration_s: parse_duration(output)
    }
  end

  defp parse_duration(output) do
    case Regex.run(~r/Duration: (\d+):(\d{2}):(\d{2})/, output) do
      [_, h, m, s] ->
        String.to_integer(h) * 3600 + String.to_integer(m) * 60 + String.to_integer(s)

      nil ->
        nil
    end
  end

  defp probe(source) do
    with {:ok, ffmpeg} <- FrameExtractor.ffmpeg_path() do
      # Exits non-zero (no output file given) but still prints the listing.
      {output, _status} =
        System.cmd(ffmpeg, ["-hide_banner", "-i", source], stderr_to_stdout: true)

      {:ok, parse_probe(output)}
    end
  end

  defp ffmpeg(args) do
    with {:ok, ffmpeg} <- FrameExtractor.ffmpeg_path() do
      case System.cmd(ffmpeg, ["-hide_banner", "-loglevel", "error" | args],
             stderr_to_stdout: true
           ) do
        {_output, 0} -> :ok
        {output, status} -> {:error, {:ffmpeg_failed, status, String.slice(output, -500, 500)}}
      end
    end
  end
end
