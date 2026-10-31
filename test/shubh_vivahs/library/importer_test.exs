defmodule ShubhVivahs.Library.ImporterTest do
  use ExUnit.Case, async: true

  alias ShubhVivahs.Library.Importer

  describe "describe/3" do
    test "parses series, season, episode, and title from an episode file" do
      assert Importer.describe(
               "/x/Game of Thrones Season 1/S01E04- Cripples, Bastards, and Broken Things.mkv",
               "series"
             ) == %{
               collection: "Game of Thrones",
               season: 1,
               episode: 4,
               title: "Cripples, Bastards, and Broken Things"
             }
    end

    test "strips release tags from the series folder and episode name" do
      assert %{collection: "Breaking Bad", season: 2, episode: 10, title: "Over"} =
               Importer.describe(
                 "/x/Breaking.Bad.S02.1080p.BluRay/Breaking.Bad.S02E10.Over.1080p.BluRay.x264.mkv",
                 "series",
                 collection: "Breaking Bad"
               )
    end

    test "falls back to a numbered title when the episode has no name" do
      assert %{title: "Episode 3"} = Importer.describe("/x/Show/S01E03.mkv", "series")

      assert %{collection: "Game of Thrones", season: 3, episode: 1, title: "Episode 1"} =
               Importer.describe(
                 "/x/Game of Thrones Season 3/Game.of.Thrones.S03E01.REPACK.720p.HDTV.x264-EVOLVE.mkv",
                 "series"
               )

      assert %{title: "Episode 2"} =
               Importer.describe(
                 "/x/Game of Thrones Season 2/Game.of.Thrones.S02E02.720p.BluRay.450MB.ShAaNiG.com.mkv",
                 "series"
               )
    end

    test "--season/--episode cover files whose names do not say" do
      assert %{collection: "Money Heist", season: 5, episode: 6, title: "Escape Valve"} =
               Importer.describe(
                 "/x/Money Heist (2021) S05 Vol.2/Money Heist . 2021 . S05 Vol.2 . EP06 - Escape Valve (1).mkv",
                 "series",
                 collection: "Money Heist",
                 season: 5,
                 episode: 6,
                 title: "Escape Valve"
               )
    end

    test "cleans movie release names down to title and year" do
      assert %{title: "EPiC Elvis Presley In Concert (2025)"} =
               Importer.describe(
                 "/x/EPiC Elvis Presley In Concert (2025) 1080p H264 EnG AC3 Sub iTA EnG-MIRCrew.mkv",
                 "movie"
               )

      assert %{title: "Jared Leto Hollywoods Dark Secret (2026)"} =
               Importer.describe(
                 "/x/Jared Leto Hollywoods Dark Secret 2026 1080p IP WEB-DL AAC2.0 x264.mkv",
                 "movie"
               )
    end

    test "--title overrides the parsed title" do
      assert %{title: "Making Of"} =
               Importer.describe("/x/another_world_making_of.mp4", "movie", title: "Making Of")
    end

    test "splits songs named 'Artist - Title'" do
      assert %{collection: "Kishore Kumar", title: "Pal Pal Dil Ke Paas"} =
               Importer.describe("/x/Kishore Kumar - Pal Pal Dil Ke Paas.mp3", "song")

      assert %{collection: "Given", title: "Solo"} =
               Importer.describe("/x/Solo.mp3", "song", collection: "Given")
    end
  end

  test "parse_probe/1 reads streams from ffmpeg's listing" do
    output = """
      Duration: 01:01:37.18, start: 0.000000, bitrate: 913 kb/s
      Stream #0:0: Video: h264 (High), yuv420p(progressive), 1280x720 (default)
      Stream #0:1(ita): Audio: ac3, 48000 Hz, 5.1(side), fltp, 384 kb/s
      Stream #0:2(eng): Audio: aac (HE-AAC), 48000 Hz, stereo, fltp (default)
      Stream #0:3(eng): Subtitle: subrip (default) (forced)
      Stream #0:5(eng): Subtitle: subrip (hearing impaired)
      Stream #0:4: Video: mjpeg (Baseline), yuvj420p, 600x600 (attached pic)
    """

    probe = Importer.parse_probe(output)

    assert probe.duration_s == 3697
    assert [%{index: 0, codec: "h264", ten_bit?: false}] = probe.video
    assert [%{index: 4}] = probe.cover

    assert [%{index: 1, language: "ita"}, %{index: 2, language: "eng", codec: "aac"}] =
             probe.audio

    assert [
             %{index: 3, codec: "subrip", language: "eng", forced?: true},
             %{index: 5, forced?: false, hearing_impaired?: true}
           ] = probe.subtitle
  end
end
