defmodule ShubhVivahsWeb.Hologram.Pages.PlayerPage do
  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias ShubhVivahs.Engagement
  alias ShubhVivahs.FaceDetection.{Movie, SceneIndex}
  alias ShubhVivahs.FocusPoll
  alias ShubhVivahs.Repo
  alias ShubhVivahs.VideoMetadata
  alias ShubhVivahs.VideoPreview
  alias ShubhVivahs.VideoSegments
  alias ShubhVivahsWeb.Hologram.Pages.AdminMoviePage
  alias ShubhVivahsWeb.Hologram.Pages.PremierePage

  route "/premiere/:id"
  param :id, :integer

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def init(params, component, server) do
    # A private movie (see Movie's :public field doc) is treated exactly
    # like a nonexistent one for anyone not signed in - same "not found"
    # path build_details/1 and every `movie && ...` guard below already
    # handle, rather than a separate error state. Signed-in visitors still
    # see it regardless of visibility, same as Dashboard/UploadPage's own
    # management view of the shared catalog.
    movie_record = Repo.get(Movie, params.id)

    movie_record =
      if movie_record && !movie_record.public && !server.user_id, do: nil, else: movie_record

    movie = build_details(movie_record)
    session_id = server.session_id
    focus_session_id = Ecto.UUID.generate()

    component =
      component
      |> put_state(:movie, movie)
      |> put_state(:session_id, session_id)
      |> put_state(:focus_session_id, focus_session_id)
      |> put_state(:movie_likes_count, (movie && Engagement.movie_likes_count(movie.id)) || 0)
      |> put_state(:movie_liked?, false)
      |> put_state(:my_movie_like_id, nil)
      |> put_state(:movie_views_count, (movie && Engagement.movie_views_count(movie.id)) || 0)
      |> put_state(:comments, (movie && Engagement.list_comments(movie.id, session_id)) || [])
      |> put_state(:commenter_name, "")
      |> put_state(:new_comment_body, "")
      |> put_state(:replying_to, nil)
      |> put_state(:reply_body, "")

    scenes_list = (movie_record && movie_scenes(movie_record, focus_session_id)) || []
    scenes_by_key = Map.new(scenes_list, &{scene_key(&1), &1})

    component =
      component
      |> put_state(:scenes, scenes_by_key)
      |> put_state(:current_scene, find_current_scene(scenes_list, 0))
      |> put_state(:scene_boundaries_json, scene_boundaries_json(scenes_list))
      |> put_state(:video_ended?, false)

    server = if movie, do: put_subscription(server, {:focus_votes, movie.id}), else: server

    {component, server}
  end

  # Only start/end timestamps — enough for the client-side JS to figure out
  # which scene index is current as the video plays, without needing the
  # full per-scene face/vote data on that side.
  defp scene_boundaries_json(scenes) do
    scenes
    |> Enum.map(&%{start_ms: &1.start_ms, end_ms: &1.end_ms})
    |> Jason.encode!()
  end

  # Detections are sampled at ~1fps, so most scenes are single-instant
  # (start_ms == end_ms) with gaps between them — an exact-range match
  # would show "no one recognised" for nearly the whole video. Instead,
  # treat a scene as the current "who's on screen" state from its start
  # until the next detected change, capped so a long stretch with no
  # faces at all eventually clears rather than showing stale info.
  @stale_scene_tolerance_ms 5_000

  # Matches the "start:end" key the inline JS already computes to detect
  # scene transitions — reusing it lets the server do an O(1) Map lookup
  # instead of a linear scan through hundreds of scenes on every change.
  defp scene_key(%{start_ms: start_ms, end_ms: end_ms}), do: "#{start_ms}:#{end_ms}"
  defp scene_key(start_ms, end_ms), do: "#{start_ms}:#{end_ms}"

  defp find_current_scene(scenes, current_ms) do
    scenes
    |> Enum.filter(&(&1.start_ms <= current_ms))
    |> List.last()
    |> case do
      nil -> nil
      scene -> if current_ms - scene.end_ms <= @stale_scene_tolerance_ms, do: scene, else: nil
    end
  end

  defp movie_scenes(movie_record, session_id) do
    votes_by_scene =
      movie_record.id
      |> FocusPoll.all_votes()
      |> Enum.group_by(&{&1.scene_start_ms, &1.scene_end_ms})

    preloaded_faces = movie_record |> Repo.preload(faces: :detections) |> Map.fetch!(:faces)
    face_labels = Map.new(preloaded_faces, fn face -> {face.id, face.label} end)

    preloaded_faces
    |> Enum.flat_map(& &1.detections)
    |> SceneIndex.scenes()
    |> Enum.map(fn scene ->
      scene_votes = Map.get(votes_by_scene, {scene.start_ms, scene.end_ms}, [])
      votes_by_face = Enum.group_by(scene_votes, & &1.face_id)

      my_voted_faces =
        scene_votes |> Enum.filter(&(&1.session_id == session_id)) |> MapSet.new(& &1.face_id)

      %{
        start_ms: scene.start_ms,
        end_ms: scene.end_ms,
        time: format_scene(scene),
        faces:
          scene.face_ids
          |> Enum.map(fn face_id ->
            face_votes = Map.get(votes_by_face, face_id, [])

            %{
              id: face_id,
              label: Map.get(face_labels, face_id) || "Face ##{face_id}",
              thumbnail_url: "/admin/faces/#{face_id}/thumbnail",
              votes: length(face_votes),
              mine?: MapSet.member?(my_voted_faces, face_id),
              voted_ats: face_votes |> voted_ats() |> Enum.map(&format_timestamp/1)
            }
          end)
          |> mark_leading()
      }
    end)
  end

  # Flags every face tied for the most votes so the panel can badge them
  # all; an all-zero scene marks no one as leading.
  defp mark_leading(faces) do
    max_votes = faces |> Enum.map(& &1.votes) |> Enum.reduce(0, &max/2)

    Enum.map(faces, &Map.put(&1, :leading?, max_votes > 0 and &1.votes == max_votes))
  end

  defp format_scene(%{start_ms: start_ms, end_ms: end_ms}) do
    if start_ms == end_ms do
      format_time(start_ms)
    else
      "#{format_time(start_ms)}–#{format_time(end_ms)}"
    end
  end

  defp format_time(ms) do
    total_seconds = div(ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    padded_seconds = seconds |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{minutes}:#{padded_seconds}"
  end

  defp voted_ats(votes),
    do: votes |> Enum.map(& &1.inserted_at) |> Enum.sort({:desc, NaiveDateTime})

  defp format_timestamp(nil), do: nil
  defp format_timestamp(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S UTC")

  defp build_details(nil), do: nil

  defp build_details(movie) do
    metadata = VideoMetadata.fetch(movie)
    qualities = build_qualities(movie, metadata)
    selected_quality = if VideoPreview.preview_ready?(movie), do: "preview", else: "source"
    segment_downloads = segment_downloads(movie, selected_quality)

    %{
      id: movie.id,
      title: movie.title || movie.path,
      status: movie.status,
      duration: VideoMetadata.format_duration(metadata.duration_ms),
      description: movie.description,
      video_url: video_url(movie.id, selected_quality),
      thumbnail_url: "/premiere/videos/#{movie.id}/thumbnail",
      download_url: download_url(movie.id, selected_quality),
      segment_downloads: segment_downloads,
      segment_count: length(segment_downloads),
      qualities: qualities,
      selected_quality: selected_quality,
      selected_quality_label: quality_label(qualities, selected_quality),
      selected_part: nil,
      part_offset_ms: 0
    }
  end

  defp build_qualities(movie, source_metadata) do
    source = %{
      key: "source",
      label: "Original · " <> VideoMetadata.describe_quality(source_metadata)
    }

    preview =
      case VideoMetadata.fetch_preview(movie) do
        nil ->
          []

        preview_metadata ->
          [
            %{
              key: "preview",
              label: "Data saver · " <> VideoMetadata.describe_quality(preview_metadata)
            }
          ]
      end

    minimal =
      case VideoMetadata.fetch_minimal(movie) do
        nil ->
          []

        minimal_metadata ->
          [
            %{
              key: "minimal",
              label: "Minimal · " <> VideoMetadata.describe_quality(minimal_metadata)
            }
          ]
      end

    [source] ++ preview ++ minimal
  end

  # Used to label the themed quality-picker dropdown's trigger button with
  # whichever quality is currently selected (see the two `dropdown` blocks
  # in the template) — a plain native <select> can't have its open option
  # list restyled, so quality picking is a daisyUI dropdown/menu instead.
  defp quality_label(qualities, key) do
    qualities |> Enum.find(&(&1.key == key)) |> Map.fetch!(:label)
  end

  # The play-detection script reads the movie id off a data-* attribute,
  # which the browser always hands back as a string.
  defp to_movie_id(id) when is_integer(id), do: id
  defp to_movie_id(id) when is_binary(id), do: String.to_integer(id)

  defp video_url(movie_id, quality), do: "/premiere/videos/#{movie_id}?quality=#{quality}"

  defp download_url(movie_id, quality),
    do: "/premiere/videos/#{movie_id}/download?quality=#{quality}"

  defp segment_downloads(movie, quality) do
    movie
    |> VideoSegments.offsets_ms(quality)
    |> Enum.with_index(1)
    |> Enum.map(fn {offset_ms, part} ->
      %{
        part: part,
        url: "/premiere/videos/#{movie.id}/download/#{part}?quality=#{quality}",
        play_url: play_url(movie.id, quality, part),
        offset_ms: offset_ms
      }
    end)
  end

  defp play_url(movie_id, quality, part),
    do: "/premiere/videos/#{movie_id}/play/#{part}?quality=#{quality}"

  # Dispatched from plain JS (see the inline script in the template) only
  # when the resolved scene key actually changes — not on every tick — so
  # playback tracking doesn't force a full page re-render 5x/second. The
  # key is the same "start:end" string the JS already computed, so this
  # is an O(1) Map lookup rather than a scan through hundreds of scenes.
  def action(:scene_changed, params, component) do
    scene = Map.get(component.state.scenes, params.scene_key)
    put_state(component, :current_scene, scene)
  end

  # Dispatched from the same polling interval that tracks scene changes,
  # rather than an "ended"/"play" event listener attached once: Hologram's
  # own client-side render replaces the <video> DOM node shortly after page
  # load, which would silently orphan a listener bound directly to it. The
  # interval already re-queries the element fresh on every tick, so it stays
  # correct regardless of node replacement.
  def action(:video_ended, _params, component) do
    put_state(component, :video_ended?, true)
  end

  def action(:video_playing, _params, component) do
    put_state(component, :video_ended?, false)
  end

  # Pausing here (rather than leaving the vote button's $click as a plain
  # command) keeps the voter from missing the scene while `cast_focus_vote`
  # makes its round trip — playback resumes once :focus_vote_updated
  # confirms this client's own vote was saved.
  #
  # The vote count/checkmark is flipped locally right here too, mirroring
  # the toggle FocusPoll.toggle_vote will perform server-side, instead of
  # waiting on the broadcast round trip to show any change — that round
  # trip previously overlapped with the video still playing, but now that
  # hover pauses playback the voter is watching the panel with nothing else
  # to look at, so the same latency reads as a stuck click. The later
  # :focus_vote_updated still lands and overwrites this guess with the
  # authoritative count, self-correcting if it was wrong.
  def action(:focus_vote_clicked, params, component) do
    JS.exec("""
    const video = document.getElementById('player-video');
    if (video) { video.pause(); }
    """)

    key = scene_key(params.scene_start_ms, params.scene_end_ms)

    scenes =
      Map.update!(component.state.scenes, key, fn scene ->
        faces =
          scene.faces
          |> Enum.map(fn face ->
            if face.id == params.face_id do
              now_mine? = !face.mine?
              %{face | mine?: now_mine?, votes: face.votes + if(now_mine?, do: 1, else: -1)}
            else
              face
            end
          end)
          |> mark_leading()

        %{scene | faces: faces}
      end)

    current_scene =
      case component.state.current_scene do
        %{start_ms: s, end_ms: e} when s == params.scene_start_ms and e == params.scene_end_ms ->
          Map.get(scenes, key)

        other ->
          other
      end

    component
    |> put_state(:scenes, scenes)
    |> put_state(:current_scene, current_scene)
    |> put_command(:cast_focus_vote,
      movie_id: params.movie_id,
      scene_start_ms: params.scene_start_ms,
      scene_end_ms: params.scene_end_ms,
      face_id: params.face_id,
      voter_id: params.voter_id
    )
  end

  # Swapping `src` via plain JS (rather than just re-rendering the `src`
  # attribute from state) lets us capture the current playback position and
  # play/paused state first and restore them once the new source has loaded,
  # instead of the browser resetting to 0:00 on every quality change. The
  # state update below keeps @movie.video_url/download_url in sync so a
  # later unrelated re-render (e.g. posting a comment) doesn't stomp the
  # JS-set src back to a stale value.
  #
  # The segmented "download in parts" links aren't updated here: unlike the
  # full download link, they depend on that quality's segment count, which
  # means running ffmpeg server-side if this quality hasn't been split into
  # parts before — so that part is handed off to a command instead, and
  # arrives a moment later via :segment_downloads_updated.
  def action(:quality_changed, params, component) do
    quality = params.quality
    movie_id = component.state.movie.id
    new_video_url = video_url(movie_id, quality)
    new_download_url = download_url(movie_id, quality)

    JS.exec("""
    const video = document.getElementById('player-video');
    if (video) {
      const time = video.currentTime;
      const wasPlaying = !video.paused;
      video.src = #{inspect(new_video_url)};
      video.addEventListener('loadedmetadata', () => {
        video.currentTime = time;
        if (wasPlaying) { video.play().catch(() => {}); }
      }, { once: true });
    }
    """)

    component
    |> put_state(:movie, %{
      component.state.movie
      | video_url: new_video_url,
        download_url: new_download_url,
        selected_quality: quality,
        selected_quality_label: quality_label(component.state.movie.qualities, quality),
        selected_part: nil,
        part_offset_ms: 0
    })
    |> put_command(:switch_download_quality, movie_id: movie_id, quality: quality)
  end

  # Jumps playback straight to one segment instead of the full video, so a
  # viewer on a slow connection can start watching a later part immediately
  # rather than waiting for (or re-buffering through) everything before it.
  # Each part's own file clock restarts at 0, but the "who's in focus" panel
  # matches scenes against movie-wide timestamps — part_offset_ms (looked up
  # from the already-known segment_downloads, not re-probed here) tells the
  # client-side polling script how much to add back to get there.
  def action(:play_part, params, component) do
    movie = component.state.movie
    new_video_url = play_url(movie.id, movie.selected_quality, params.part)

    offset_ms =
      movie.segment_downloads |> Enum.find(&(&1.part == params.part)) |> Map.fetch!(:offset_ms)

    JS.exec("""
    const video = document.getElementById('player-video');
    if (video) {
      video.src = #{inspect(new_video_url)};
      video.addEventListener('loadedmetadata', () => {
        video.currentTime = 0;
        video.play().catch(() => {});
      }, { once: true });
    }
    """)

    put_state(component, :movie, %{
      movie
      | video_url: new_video_url,
        selected_part: params.part,
        part_offset_ms: offset_ms
    })
  end

  def action(:play_full, _params, component) do
    movie = component.state.movie
    new_video_url = video_url(movie.id, movie.selected_quality)

    JS.exec("""
    const video = document.getElementById('player-video');
    if (video) {
      video.src = #{inspect(new_video_url)};
      video.addEventListener('loadedmetadata', () => {
        video.currentTime = 0;
        video.play().catch(() => {});
      }, { once: true });
    }
    """)

    put_state(component, :movie, %{
      movie
      | video_url: new_video_url,
        selected_part: nil,
        part_offset_ms: 0
    })
  end

  def action(:segment_downloads_updated, params, component) do
    put_state(component, :movie, %{
      component.state.movie
      | segment_downloads: params.segment_downloads,
        segment_count: length(params.segment_downloads)
    })
  end

  def action(:update_commenter_name, params, component) do
    put_state(component, :commenter_name, params.event.value)
  end

  def action(:update_comment_body, params, component) do
    put_state(component, :new_comment_body, params.event.value)
  end

  def action(:update_reply_body, params, component) do
    put_state(component, :reply_body, params.event.value)
  end

  def action(:start_reply, params, component) do
    component
    |> put_state(:replying_to, params.comment_id)
    |> put_state(:reply_body, "")
  end

  def action(:cancel_reply, _params, component) do
    component
    |> put_state(:replying_to, nil)
    |> put_state(:reply_body, "")
  end

  def action(:movie_like_added, params, component) do
    component
    |> put_state(:movie_likes_count, params.count)
    |> put_state(:movie_liked?, true)
    |> put_state(:my_movie_like_id, params.like_id)
  end

  def action(:movie_like_removed, params, component) do
    component
    |> put_state(:movie_likes_count, params.count)
    |> put_state(:movie_liked?, false)
    |> put_state(:my_movie_like_id, nil)
  end

  # Dispatched from the inline script (see the setInterval block in the
  # template) the first time it observes the video playing - guarded
  # client-side so replaying/pausing the same movie doesn't record repeat
  # views within one page load.
  def action(:movie_played, params, component) do
    put_command(component, :record_movie_view, movie_id: params.movie_id)
  end

  def action(:movie_view_recorded, params, component) do
    put_state(component, :movie_views_count, params.count)
  end

  def action(:comment_added, params, component) do
    component
    |> put_state(:comments, params.comments)
    |> put_state(:new_comment_body, "")
  end

  def action(:reply_added, params, component) do
    component
    |> put_state(:comments, params.comments)
    |> put_state(:reply_body, "")
    |> put_state(:replying_to, nil)
  end

  def action(:comments_updated, params, component) do
    put_state(component, :comments, params.comments)
  end

  def action(:focus_vote_updated, params, component) do
    my_session_id = component.state.focus_session_id
    is_mine = params.voter_session_id == my_session_id
    key = scene_key(params.scene_start_ms, params.scene_end_ms)

    scenes =
      Map.update!(component.state.scenes, key, fn scene ->
        faces =
          scene.faces
          |> Enum.map(fn face ->
            votes = Map.get(params.counts, face.id, 0)
            voted_ats = params.voted_ats |> Map.get(face.id, []) |> Enum.map(&format_timestamp/1)

            mine? =
              if is_mine and face.id == params.face_id, do: params.voted?, else: face.mine?

            %{face | votes: votes, mine?: mine?, voted_ats: voted_ats}
          end)
          |> mark_leading()

        %{scene | faces: faces}
      end)

    current_scene =
      case component.state.current_scene do
        %{start_ms: s, end_ms: e} when s == params.scene_start_ms and e == params.scene_end_ms ->
          Map.get(scenes, key)

        other ->
          other
      end

    JS.exec("""
    if (#{is_mine} && !window.__focusPanelHovered) {
      const video = document.getElementById('player-video');
      if (video) { video.play().catch(() => {}); }
    }
    """)

    component
    |> put_state(:scenes, scenes)
    |> put_state(:current_scene, current_scene)
  end

  def command(:switch_download_quality, %{movie_id: movie_id, quality: quality}, server) do
    movie = Repo.get!(Movie, movie_id)

    put_action(server, :segment_downloads_updated,
      segment_downloads: segment_downloads(movie, quality)
    )
  end

  def command(:like_movie, %{movie_id: movie_id, like_id: nil}, server) do
    {like_id, count} = Engagement.add_movie_like(movie_id, server.session_id)
    put_action(server, :movie_like_added, count: count, like_id: like_id)
  end

  def command(:like_movie, %{movie_id: movie_id, like_id: like_id}, server) do
    count = Engagement.remove_movie_like(like_id, movie_id, server.session_id)
    put_action(server, :movie_like_removed, count: count)
  end

  def command(:record_movie_view, %{movie_id: movie_id}, server) do
    count = Engagement.record_movie_view(to_movie_id(movie_id), server.session_id)
    put_action(server, :movie_view_recorded, count: count)
  end

  def command(:add_comment, %{movie_id: movie_id, body: body, name: name}, server) do
    Engagement.add_comment(movie_id, body, server.session_id, name)
    comments = Engagement.list_comments(movie_id, server.session_id)
    put_action(server, :comment_added, comments: comments)
  end

  def command(
        :add_reply,
        %{movie_id: movie_id, parent_id: parent_id, body: body, name: name},
        server
      ) do
    Engagement.add_comment(movie_id, body, server.session_id, name, parent_id)
    comments = Engagement.list_comments(movie_id, server.session_id)
    put_action(server, :reply_added, comments: comments)
  end

  def command(:like_comment, %{movie_id: movie_id, comment_id: comment_id}, server) do
    Engagement.toggle_comment_like(comment_id, server.session_id)
    comments = Engagement.list_comments(movie_id, server.session_id)
    put_action(server, :comments_updated, comments: comments)
  end

  def command(:delete_comment, %{movie_id: movie_id, comment_id: comment_id}, server) do
    Engagement.delete_comment(comment_id, server.session_id)
    comments = Engagement.list_comments(movie_id, server.session_id)
    put_action(server, :comments_updated, comments: comments)
  end

  def command(
        :cast_focus_vote,
        %{
          movie_id: movie_id,
          scene_start_ms: scene_start_ms,
          scene_end_ms: scene_end_ms,
          face_id: face_id,
          voter_id: voter_id
        },
        server
      ) do
    {counts, voted_ats, voted?} =
      FocusPoll.toggle_vote(movie_id, scene_start_ms, scene_end_ms, face_id, voter_id)

    put_broadcast(server, {:focus_votes, movie_id}, :focus_vote_updated,
      scene_start_ms: scene_start_ms,
      scene_end_ms: scene_end_ms,
      counts: counts,
      voted_ats: voted_ats,
      voter_session_id: voter_id,
      face_id: face_id,
      voted?: voted?
    )
  end

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <div class="max-w-5xl mx-auto">
        <Link to={PremierePage} class="link link-hover text-sm">&larr; Back to Premiere Hall</Link>

        {%if @movie == nil}
          <div class="card card-stock shadow-xl mt-4">
            <div class="card-body">
              <p class="text-base-content/70">This film could not be found.</p>
            </div>
          </div>
        {%else}
          <h1 class="font-display text-2xl mt-4 mb-1">{@movie.title}</h1>
          <div class="mb-4">
            <div class="flex items-center gap-3">
              <p class="text-sm text-base-content/70">{@movie.duration}</p>
              <Link to={AdminMoviePage, id: @movie.id} class="btn btn-xs btn-secondary">
                Admin View ⚙
              </Link>
            </div>
            {%if @movie.description}
              <p class="text-sm text-base-content/70 mt-1">{@movie.description}</p>
            {/if}
          </div>

          <div class="relative flex flex-col lg:flex-row gap-4">
            <div class="flex-1 min-w-0 lg:pr-[25rem]">
              <div class="relative">
                <video
                  id="player-video"
                  data-scene-boundaries={@scene_boundaries_json}
                  data-movie-id={@movie.id}
                  data-part-offset-ms={@movie.part_offset_ms}
                  controls
                  poster={@movie.thumbnail_url}
                  class="w-full rounded-box shadow-xl"
                  src={@movie.video_url}
                >
                </video>

                {%if @video_ended?}
                  <div class="absolute inset-0 flex items-center justify-center bg-black/70 rounded-box">
                    <div class="flex flex-col items-center gap-3 p-4">
                      <p class="text-white text-sm font-display">
                        {%if @movie.selected_part}Part {@movie.selected_part} finished{%else}Video finished{/if}
                      </p>
                      <div class="flex flex-wrap justify-center gap-2">
                        {%if @movie.selected_part && @movie.selected_part > 1}
                          <button
                            $click={:play_part, part: @movie.selected_part - 1}
                            class="btn btn-sm btn-outline btn-primary bg-black/40"
                          >
                            ◀ Previous part
                          </button>
                        {/if}

                        {%if @movie.selected_part}
                          <button
                            $click={:play_part, part: @movie.selected_part}
                            class="btn btn-sm btn-outline btn-primary bg-black/40"
                          >
                            ↻ Replay
                          </button>
                        {%else}
                          <button $click="play_full" class="btn btn-sm btn-outline btn-primary bg-black/40">
                            ↻ Replay
                          </button>
                        {/if}

                        {%if @movie.selected_part}
                          {%if @movie.selected_part < @movie.segment_count}
                            <button
                              $click={:play_part, part: @movie.selected_part + 1}
                              class="btn btn-sm btn-primary"
                            >
                              Next part ▶
                            </button>
                          {/if}
                        {%else}
                          {%if @movie.segment_count > 0}
                            <button $click={:play_part, part: 1} class="btn btn-sm btn-primary">
                              Play in parts ▶
                            </button>
                          {/if}
                        {/if}
                      </div>
                    </div>
                  </div>
                {/if}
              </div>

              {%if length(@movie.qualities) > 1}
                <div class="flex items-center gap-2 mt-2 flex-wrap">
                  <span class="text-xs text-base-content/60">Quality</span>
                  <div class="dropdown dropdown-bottom">
                    <div tabindex="0" role="button" class="btn btn-sm btn-outline h-auto py-2">
                      {@movie.selected_quality_label} ▾
                    </div>
                    <ul tabindex="0" class="dropdown-content menu menu-sm card-stock rounded-box z-10 mt-1 w-64 max-w-[calc(100vw-6rem)] p-2 shadow">
                      {%for quality <- @movie.qualities}
                        <li>
                          <a
                            $click={:quality_changed, quality: quality.key}
                            class={if quality.key == @movie.selected_quality do "active" else "" end}
                          >
                            {quality.label}
                          </a>
                        </li>
                      {/for}
                    </ul>
                  </div>
                </div>
              {/if}

              {%if @movie.segment_count > 0}
                <div class="flex items-center gap-2 mt-2 flex-wrap">
                  <span class="text-xs text-base-content/60">Play in parts</span>
                  <div class="dropdown dropdown-bottom">
                    <div tabindex="0" role="button" class="btn btn-sm btn-outline h-auto py-2">
                      {%if @movie.selected_part}Part {@movie.selected_part}{%else}Full video{/if} ▾
                    </div>
                    <ul tabindex="0" class="dropdown-content menu menu-sm card-stock rounded-box z-10 mt-1 w-44 max-w-[calc(100vw-6rem)] p-2 shadow">
                      <li>
                        <a $click="play_full" class={if @movie.selected_part == nil do "active" else "" end}>
                          Full video
                        </a>
                      </li>
                      {%for segment <- @movie.segment_downloads}
                        <li>
                          <a
                            $click={:play_part, part: segment.part}
                            class={if @movie.selected_part == segment.part do "active" else "" end}
                          >
                            Part {segment.part}
                          </a>
                        </li>
                      {/for}
                    </ul>
                  </div>
                  <span class="text-xs text-base-content/50">Jump in without waiting for the whole video</span>
                </div>
              {/if}

              <script>
                {%raw}
                (function () {
                  if (window.__focusPollAttached) { return; }
                  window.__focusPollAttached = true;

                  var scenes = null;
                  var staleToleranceMs = 5000;
                  var lastKey = "unset";
                  var viewRecordedForMovieId = null;
                  var wasEnded = false;

                  function resolveSceneIndex(currentMs) {
                    var idx = -1;
                    for (var i = 0; i < scenes.length; i++) {
                      if (scenes[i].start_ms <= currentMs) {
                        idx = i;
                      } else {
                        break;
                      }
                    }
                    if (idx === -1) { return -1; }
                    if (currentMs - scenes[idx].end_ms > staleToleranceMs) { return -1; }
                    return idx;
                  }

                  setInterval(function () {
                    var video = document.getElementById('player-video');
                    if (!video) { return; }

                    if (scenes === null) {
                      scenes = JSON.parse(video.dataset.sceneBoundaries || "[]");
                    }

                    var partOffsetMs = parseInt(video.dataset.partOffsetMs, 10) || 0;
                    var currentMs = partOffsetMs + Math.round(video.currentTime * 1000);
                    var idx = resolveSceneIndex(currentMs);
                    var scene = idx === -1 ? null : scenes[idx];
                    var key = scene ? (scene.start_ms + ":" + scene.end_ms) : "none";

                    if (key !== lastKey) {
                      lastKey = key;
                      Hologram.dispatchAction('scene_changed', 'page', { scene_key: key });
                    }

                    var movieId = video.dataset.movieId;
                    if (!video.paused && viewRecordedForMovieId !== movieId) {
                      viewRecordedForMovieId = movieId;
                      Hologram.dispatchAction('movie_played', 'page', { movie_id: movieId });
                    }

                    if (video.ended && !wasEnded) {
                      wasEnded = true;
                      Hologram.dispatchAction('video_ended', 'page', {});
                    } else if (!video.ended && wasEnded) {
                      wasEnded = false;
                      Hologram.dispatchAction('video_playing', 'page', {});
                    }
                  }, 200);
                })();

                // Pauses the video while the pointer is over the focus-vote
                // panel, so a viewer has time to read faces and click a vote
                // before the scene moves on, and resumes on mouse-out — but
                // only if the video was actually playing when the hover
                // started (so hovering never *starts* a paused video).
                // mouseenter/mouseleave don't bubble, so this delegates from
                // `document` in the capture phase instead of binding
                // directly to the panel — which Hologram's own re-renders
                // could otherwise orphan — and matches on `e.target` being
                // the panel itself (not a descendant), since entering a
                // child element like a vote button fires its own
                // mouseenter/mouseleave without one for the panel too.
                (function () {
                  if (window.__focusHoverAttached) { return; }
                  window.__focusHoverAttached = true;
                  window.__focusPanelHovered = false;

                  var wasPlayingBeforeHover = false;

                  function setHoverStatus(text) {
                    var status = document.getElementById('focus-hover-status');
                    if (status) { status.textContent = text; }
                  }

                  document.addEventListener('mouseenter', function (e) {
                    if (!e.target || e.target.id !== 'focus-vote-panel') { return; }
                    window.__focusPanelHovered = true;
                    setHoverStatus('⏸ Paused');
                    var video = document.getElementById('player-video');
                    if (!video) { return; }
                    wasPlayingBeforeHover = !video.paused;
                    video.pause();
                  }, true);

                  document.addEventListener('mouseleave', function (e) {
                    if (!e.target || e.target.id !== 'focus-vote-panel') { return; }
                    window.__focusPanelHovered = false;
                    setHoverStatus('▶ Playing');
                    var video = document.getElementById('player-video');
                    if (video && wasPlayingBeforeHover) { video.play().catch(function () {}); }
                  }, true);
                })();
                {/raw}
              </script>
            </div>

            <div class="flex flex-col lg:absolute lg:inset-y-0 lg:right-0 lg:w-96">
              <div class="card card-stock shadow flex-1 flex flex-col min-h-0 overflow-hidden">
                <div id="focus-vote-panel" class="card-body py-4 flex-1 flex flex-col min-h-0">
                  <h2 class="font-display text-lg mb-1">Who's in focus?</h2>
                  <div class="flex items-center gap-2 mb-1 flex-wrap">
                    <span class="text-[0.65rem] text-base-content/50">
                      Hover here to pause and vote — move away to resume
                    </span>
                    <span id="focus-hover-status" class="badge badge-outline badge-xs whitespace-nowrap">
                      ▶ Playing
                    </span>
                  </div>
                  {%if @current_scene == nil}
                    <p class="text-sm text-base-content/60">No one recognised at this point in the video.</p>
                  {%else}
                    <div class="flex items-center gap-2 mb-2">
                      <span class="badge badge-outline whitespace-nowrap">{@current_scene.time}</span>
                      <span class="text-xs text-base-content/60 truncate">Vote live for who's on screen</span>
                    </div>
                    <div class="flex-1 min-h-0 flex flex-wrap gap-2 overflow-y-auto content-start">
                      {%for face <- @current_scene.faces}
                        <button
                          $click={:focus_vote_clicked, movie_id: @movie.id, scene_start_ms: @current_scene.start_ms, scene_end_ms: @current_scene.end_ms, face_id: face.id, voter_id: @focus_session_id}
                          class={if face.mine? do "btn btn-primary h-auto py-2 px-3 gap-2" else "btn btn-outline h-auto py-2 px-3 gap-2" end}
                        >
                          <img src={face.thumbnail_url} class="w-10 h-10 rounded-full object-cover shrink-0" />
                          <span class="text-xs normal-case text-left leading-tight">
                            {face.label}
                            {%if face.leading?}
                              <span class="badge badge-secondary badge-xs align-middle gap-1">🏆 leading</span>
                            {/if}
                            <br />{face.votes} vote(s)
                            {%if face.mine?}
                              <span class="block font-semibold">✓ your vote</span>
                            {/if}
                          </span>
                        </button>
                      {/for}
                    </div>
                  {/if}
                </div>
              </div>
            </div>
          </div>

          <div class="mt-4 flex items-center gap-2">
            <button
              $click={command: :like_movie, params: %{movie_id: @movie.id, like_id: @my_movie_like_id}}
              class={if @movie_liked? do "btn btn-sm btn-error" else "btn btn-sm btn-outline" end}
            >
              {%if @movie_liked?}♥ Liked{%else}♥ Like{/if}
            </button>
            <span class="text-sm text-base-content/70">{@movie_likes_count} like(s)</span>
            <span class="text-sm text-base-content/50">· {@movie_views_count} view(s)</span>
          </div>

          <div class="mt-6 card card-stock shadow">
            <div class="card-body py-4">
              <h2 class="font-display text-sm mb-3">Download</h2>

              {%if length(@movie.qualities) > 1}
                <div class="flex items-center gap-2 mb-3 flex-wrap">
                  <span class="text-xs text-base-content/60">Quality</span>
                  <div class="dropdown dropdown-bottom">
                    <div tabindex="0" role="button" class="btn btn-sm btn-outline h-auto py-2">
                      {@movie.selected_quality_label} ▾
                    </div>
                    <ul tabindex="0" class="dropdown-content menu menu-sm card-stock rounded-box z-10 mt-1 w-64 max-w-[calc(100vw-6rem)] p-2 shadow">
                      {%for quality <- @movie.qualities}
                        <li>
                          <a
                            $click={:quality_changed, quality: quality.key}
                            class={if quality.key == @movie.selected_quality do "active" else "" end}
                          >
                            {quality.label}
                          </a>
                        </li>
                      {/for}
                    </ul>
                  </div>
                </div>
              {/if}

              <div class="flex flex-wrap items-center gap-2">
                <a href={@movie.download_url} download class="btn btn-sm btn-primary">
                  Download full movie
                </a>

                {%if @movie.segment_count > 0}
                  <div class="dropdown dropdown-bottom">
                    <div tabindex="0" role="button" class="btn btn-sm btn-outline">
                      Download in parts ({@movie.segment_count}) ▾
                    </div>
                    <ul
                      tabindex="0"
                      class="dropdown-content menu menu-sm bg-base-100 rounded-box z-10 mt-1 w-44 p-2 shadow"
                    >
                      {%for segment <- @movie.segment_downloads}
                        <li>
                          <a href={segment.url} download>Part {segment.part}</a>
                        </li>
                      {/for}
                    </ul>
                  </div>
                {/if}
              </div>

              <p class="text-xs text-base-content/60 mt-2">
                Parts are independently playable clips — no need to join them. Handy on a slow
                connection since each part can be retried on its own instead of restarting the
                whole download.
              </p>
            </div>
          </div>

          <div class="mt-8">
            <h2 class="font-display text-lg mb-3">Comments</h2>

            <form $submit={command: :add_comment, params: %{movie_id: @movie.id, body: @new_comment_body, name: @commenter_name}}>
              <div class="flex flex-col gap-2 mb-4">
                <input
                  type="text"
                  value={@commenter_name}
                  $change="update_commenter_name"
                  placeholder="Your name"
                  class="input input-bordered input-sm w-full sm:w-64"
                />
                <textarea
                  value={@new_comment_body}
                  $change="update_comment_body"
                  placeholder="Add a comment..."
                  rows="3"
                  class="textarea textarea-bordered textarea-sm w-full"
                />
                <button type="submit" class="btn btn-sm btn-primary self-end">Post</button>
              </div>
            </form>

            <div class="max-h-96 overflow-y-auto pr-1">
            {%if @comments == []}
              <p class="text-sm text-base-content/60">No comments yet.</p>
            {%else}
              <div class="flex flex-col gap-3">
                {%for comment <- @comments}
                  <div class="card card-stock shadow">
                    <div class="card-body py-3">
                      <div class="flex items-start gap-2 sm:gap-3">
                        <div class="avatar avatar-placeholder shrink-0">
                          <div class="bg-neutral text-neutral-content rounded-full w-6 sm:w-8">
                            <span class="text-xs">{comment.author_initial}</span>
                          </div>
                        </div>
                        <div class="flex-1 min-w-0">
                          <div class="flex items-center justify-between flex-wrap gap-x-3 gap-y-1">
                            <div class="min-w-0">
                              <p class="text-xs font-semibold text-base-content/80">{comment.author_name}</p>
                              <p class="text-sm">{comment.body}</p>
                            </div>
                            <div class="flex items-center gap-2 shrink-0">
                              <button
                                $click={command: :like_comment, params: %{movie_id: @movie.id, comment_id: comment.id}}
                                class={if comment.liked? do "btn btn-xs btn-error" else "btn btn-xs btn-ghost" end}
                              >
                                ♥ {comment.likes_count}
                              </button>
                              <button
                                $click={action: :start_reply, params: %{comment_id: comment.id}}
                                class="btn btn-xs btn-ghost"
                              >
                                Reply
                              </button>
                              {%if comment.own?}
                                <button
                                  $click={command: :delete_comment, params: %{movie_id: @movie.id, comment_id: comment.id}}
                                  class="btn btn-xs btn-ghost text-error"
                                >
                                  Delete
                                </button>
                              {/if}
                            </div>
                          </div>

                          <form
                            $submit={command: :add_reply, params: %{movie_id: @movie.id, parent_id: comment.id, body: @reply_body, name: @commenter_name}}
                            class={if @replying_to == comment.id do "mt-2 ml-4" else "hidden" end}
                          >
                            <div class="flex flex-col gap-2">
                              <textarea
                                value={@reply_body}
                                $change="update_reply_body"
                                placeholder="Write a reply..."
                                rows="2"
                                class="textarea textarea-bordered textarea-xs w-full"
                              />
                              <div class="flex gap-2 self-end">
                                <button type="submit" class="btn btn-xs btn-primary">Reply</button>
                                <button type="button" $click="cancel_reply" class="btn btn-xs btn-ghost">
                                  Cancel
                                </button>
                              </div>
                            </div>
                          </form>

                          {%if comment.replies != []}
                            <div class="flex flex-col gap-3 mt-3 ml-2 sm:ml-6 border-l-2 border-base-300 pl-1.5 sm:pl-3">
                              {%for reply <- comment.replies}
                                <div class="flex items-start gap-1 sm:gap-2">
                                  <div class="avatar avatar-placeholder shrink-0">
                                    <div class="bg-neutral text-neutral-content rounded-full w-5 sm:w-6">
                                      <span class="text-[0.65rem]">{reply.author_initial}</span>
                                    </div>
                                  </div>
                                  <div class="flex-1 min-w-0 flex items-center justify-between flex-wrap gap-x-3 gap-y-1">
                                    <div class="min-w-0">
                                      <p class="text-xs font-semibold text-base-content/80">{reply.author_name}</p>
                                      <p class="text-xs sm:text-sm">{reply.body}</p>
                                    </div>
                                    <div class="flex items-center gap-2 shrink-0">
                                      <button
                                        $click={command: :like_comment, params: %{movie_id: @movie.id, comment_id: reply.id}}
                                        class={if reply.liked? do "btn btn-xs btn-error" else "btn btn-xs btn-ghost" end}
                                      >
                                        ♥ {reply.likes_count}
                                      </button>
                                      {%if reply.own?}
                                        <button
                                          $click={command: :delete_comment, params: %{movie_id: @movie.id, comment_id: reply.id}}
                                          class="btn btn-xs btn-ghost text-error"
                                        >
                                          Delete
                                        </button>
                                      {/if}
                                    </div>
                                  </div>
                                </div>
                              {/for}
                            </div>
                          {/if}
                        </div>
                      </div>
                    </div>
                  </div>
                {/for}
              </div>
            {/if}
            </div>
          </div>
        {/if}
      </div>
    </div>
    """
  end
end
