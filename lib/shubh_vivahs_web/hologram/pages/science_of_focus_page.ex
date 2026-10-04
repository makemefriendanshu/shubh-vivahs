defmodule ShubhVivahsWeb.Hologram.Pages.ScienceOfFocusPage do
  @moduledoc """
  The "why" behind the Focus Poll: explains that face detection/clustering
  (see `ShubhVivahs.FaceDetection`) only builds the scene timeline —
  deciding who a scene is *about* is left entirely to viewer votes (see
  `ShubhVivahs.FocusPoll` and `mark_leading/1` below, which marks a
  face "Leading" purely on vote count, no AI scoring involved). Also
  hosts a live demo: the movie behind the single (movie, scene) pair with
  the most votes cast so far, playable and votable right on this page.
  The "Who's in focus?" panel tracks video.currentTime as it plays and
  updates live — same client-side polling + `scene_changed`-style action
  as `PlayerPage`, just scoped to one demo movie instead of whichever
  movie is being watched. Same `FocusPoll.toggle_vote/5` + broadcast
  plumbing as `PlayerPage` and `AdminMoviePage` for the actual voting.
  """

  use Hologram.Page
  use Hologram.JS

  import Ecto.Query

  alias Hologram.UI.Link
  alias ShubhVivahs.FaceDetection
  alias ShubhVivahs.FaceDetection.{Movie, SceneIndex}
  alias ShubhVivahs.FocusPoll
  alias ShubhVivahs.FocusPoll.Vote
  alias ShubhVivahs.Repo
  alias ShubhVivahsWeb.Hologram.Pages.PremierePage

  route "/science-of-focus"

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  @engine_steps [
    %{label: "Video Stream", icon: "hero-video-camera"},
    %{label: "Face Detection (AI)", icon: "hero-face-smile"},
    %{label: "Face Clustering (AI)", icon: "hero-square-3-stack-3d"},
    %{label: "Scene Timeline", icon: "hero-film"},
    %{label: "Community Vote", icon: "hero-hand-raised"},
    %{label: "Leading Face", icon: "hero-trophy"}
  ]

  # Detections are sampled at ~1fps, same tolerance PlayerPage uses so a
  # scene's "who's on screen" state holds until the next detected change
  # rather than flickering to "no one" between samples.
  @stale_scene_tolerance_ms 5_000

  def init(_params, component, server) do
    leading_faces = top_voted_face_per_movie(FaceDetection.list_public_movies_ordered())
    top_face = List.first(leading_faces)

    focus_session_id = Ecto.UUID.generate()
    demo = build_demo(focus_session_id)

    component =
      component
      |> put_state(:engine_steps, @engine_steps)
      |> put_state(:top_face, top_face)
      |> put_state(:leading_faces, leading_faces)
      |> put_state(:focus_session_id, focus_session_id)
      |> put_state(:demo_open, false)
      |> put_state(:demo_movie_id, demo.movie_id)
      |> put_state(:demo_seed_scene, demo.seed_scene)
      |> put_state(:demo_leading_face, demo.leading_face)
      |> put_state(:demo_scenes, demo.scenes_by_key)
      |> put_state(:demo_scene_boundaries_json, demo.boundaries_json)
      |> put_state(:demo_current_scene, demo.seed_scene)

    server =
      if demo.movie_id, do: put_subscription(server, {:focus_votes, demo.movie_id}), else: server

    {component, server}
  end

  # One entry per movie — its face with the most votes cast anywhere in
  # it, so the gallery on this page shows real "who mattered" faces
  # instead of an arbitrary recent-by-id sample. Movies with no votes yet
  # are left out rather than padded with a meaningless face.
  defp top_voted_face_per_movie(movies) do
    movies
    |> Enum.map(fn movie ->
      case movie.id |> FocusPoll.face_totals() |> Enum.max_by(&elem(&1, 1), fn -> nil end) do
        {face_id, votes} when votes > 0 ->
          %{
            movie_id: movie.id,
            movie_title: movie.title || movie.path,
            votes: votes,
            thumbnail_url: "/admin/faces/#{face_id}/thumbnail"
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.votes, :desc)
  end

  # Picks the single (movie, scene) pair with the most votes cast anywhere
  # on the site, so "try it yourself" always demos a scene real viewers
  # actually engaged with, then loads that whole movie's scene timeline
  # (not just the one scene) so the "who's in focus" panel can track
  # playback across the full video, same as PlayerPage does for whichever
  # movie is being watched.
  defp build_demo(focus_session_id) do
    top =
      Vote
      |> group_by([v], [v.movie_id, v.scene_start_ms, v.scene_end_ms])
      |> select([v], {v.movie_id, v.scene_start_ms, v.scene_end_ms, count(v.id)})
      |> order_by([v], desc: count(v.id))
      |> limit(1)
      |> Repo.all()
      |> List.first()

    case top do
      {movie_id, start_ms, end_ms, _count} ->
        {scenes_by_key, boundaries_json} = load_movie_scenes(movie_id, focus_session_id)
        seed_key = scene_key(start_ms, end_ms)
        seed_scene = Map.get(scenes_by_key, seed_key) || empty_scene(start_ms, end_ms, movie_id)
        leading_face = Enum.find(seed_scene.faces, & &1.leading?)

        %{
          movie_id: movie_id,
          scenes_by_key: scenes_by_key,
          boundaries_json: boundaries_json,
          seed_scene: seed_scene,
          leading_face: leading_face
        }

      nil ->
        %{
          movie_id: nil,
          scenes_by_key: %{},
          boundaries_json: "[]",
          seed_scene: nil,
          leading_face: nil
        }
    end
  end

  defp empty_scene(start_ms, end_ms, movie_id) do
    %{
      start_ms: start_ms,
      end_ms: end_ms,
      time: format_scene_time(start_ms, end_ms),
      video_src: video_src(movie_id, start_ms),
      faces: []
    }
  end

  defp load_movie_scenes(movie_id, session_id) do
    preloaded = Movie |> Repo.get!(movie_id) |> Repo.preload(faces: :detections)
    face_labels = Map.new(preloaded.faces, fn face -> {face.id, face.label} end)

    votes_by_scene =
      movie_id
      |> FocusPoll.all_votes()
      |> Enum.group_by(&{&1.scene_start_ms, &1.scene_end_ms})

    scenes_list =
      preloaded.faces
      |> Enum.flat_map(& &1.detections)
      |> SceneIndex.scenes()
      |> Enum.map(fn scene ->
        scene_votes = Map.get(votes_by_scene, {scene.start_ms, scene.end_ms}, [])
        votes_by_face = Enum.group_by(scene_votes, & &1.face_id)

        my_voted_faces =
          scene_votes |> Enum.filter(&(&1.session_id == session_id)) |> MapSet.new(& &1.face_id)

        faces =
          scene.face_ids
          |> Enum.map(fn face_id ->
            face_votes = Map.get(votes_by_face, face_id, [])

            %{
              id: face_id,
              label: Map.get(face_labels, face_id) || "Face ##{face_id}",
              votes: length(face_votes),
              mine?: MapSet.member?(my_voted_faces, face_id),
              thumbnail_url: "/admin/faces/#{face_id}/thumbnail"
            }
          end)
          |> mark_leading()

        %{
          start_ms: scene.start_ms,
          end_ms: scene.end_ms,
          time: format_scene_time(scene.start_ms, scene.end_ms),
          video_src: video_src(movie_id, scene.start_ms),
          faces: faces
        }
      end)

    scenes_by_key = Map.new(scenes_list, &{scene_key(&1.start_ms, &1.end_ms), &1})

    boundaries_json =
      scenes_list
      |> Enum.map(&%{start_ms: &1.start_ms, end_ms: &1.end_ms})
      |> Jason.encode!()

    {scenes_by_key, boundaries_json}
  end

  defp scene_key(start_ms, end_ms), do: "#{start_ms}:#{end_ms}"

  defp video_src(movie_id, start_ms) do
    "/premiere/videos/#{movie_id}#t=#{div(start_ms, 1000)}"
  end

  defp format_scene_time(start_ms, end_ms) do
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

  # No AI weighting here on purpose — see the module doc and the "Your
  # Vote" section's copy: the leading face is whichever has the most
  # votes, full stop.
  #
  # Plain reduce rather than Enum.max/2 with an empty-list fallback — this
  # runs client-side too (called from action(:focus_vote_updated, ...)),
  # and Hologram's client-side Enum.max/2 doesn't support that fallback
  # arg the way real Elixir does (crashes instead of running it), same
  # issue AdminMoviePage works around for Enum.min/2.
  defp mark_leading(faces) do
    max_votes = Enum.reduce(faces, 0, fn face, acc -> max(face.votes, acc) end)
    Enum.map(faces, &Map.put(&1, :leading?, max_votes > 0 and &1.votes == max_votes))
  end

  def action(:open_demo, _params, component) do
    component
    |> put_state(:demo_open, true)
    |> put_action(name: :start_demo_tracking, params: %{}, delay: 0)
  end

  # Deferred one tick past :open_demo (see the `delay: 0` above) so the
  # <video data-scene-boundaries="..."> element the interval reads from
  # has actually been patched into the DOM first — mirrors how
  # AdminMoviePage sequences :scene_shown -> :play_scene_video for the
  # same reason.
  def action(:start_demo_tracking, _params, component) do
    JS.exec("""
    (function () {
      if (window.__scienceDemoInterval) { clearInterval(window.__scienceDemoInterval); }

      var scenes = null;
      var staleToleranceMs = #{@stale_scene_tolerance_ms};
      var lastKey = "unset";

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

      window.__scienceDemoInterval = setInterval(function () {
        var video = document.getElementById('science-demo-video');
        if (!video) {
          clearInterval(window.__scienceDemoInterval);
          window.__scienceDemoInterval = null;
          return;
        }

        if (scenes === null) {
          scenes = JSON.parse(video.dataset.sceneBoundaries || "[]");
        }

        var currentMs = Math.round(video.currentTime * 1000);
        var idx = resolveSceneIndex(currentMs);
        var scene = idx === -1 ? null : scenes[idx];
        var key = scene ? (scene.start_ms + ":" + scene.end_ms) : "none";

        if (key !== lastKey) {
          lastKey = key;
          Hologram.dispatchAction('demo_scene_changed', 'page', { scene_key: key });
        }
      }, 200);
    })();
    """)

    component
  end

  def action(:close_demo, _params, component) do
    JS.exec("""
    if (window.__scienceDemoInterval) {
      clearInterval(window.__scienceDemoInterval);
      window.__scienceDemoInterval = null;
    }
    """)

    put_state(component, :demo_open, false)
  end

  # Dispatched only when the resolved scene key actually changes (see the
  # JS in :start_demo_tracking) — an O(1) Map lookup rather than a scan
  # through the movie's scenes on every poll tick.
  def action(:demo_scene_changed, params, component) do
    scene = Map.get(component.state.demo_scenes, params.scene_key)
    put_state(component, :demo_current_scene, scene)
  end

  # Flips the clicked face vote/count in the demo panel right away,
  # mirroring the toggle the cast_focus_vote command will perform
  # server-side, instead of leaving the button looking unresponsive until
  # the broadcast round trip lands (see the same fix in PlayerPage and
  # AdminMoviePage). focus_vote_updated below still lands moments later
  # and reconciles this guess with the authoritative counts.
  def action(:demo_focus_vote_clicked, params, component) do
    key = scene_key(params.scene_start_ms, params.scene_end_ms)

    demo_scenes =
      Map.update!(component.state.demo_scenes, key, fn scene ->
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

    demo_current_scene =
      case component.state.demo_current_scene do
        %{start_ms: s, end_ms: e} when s == params.scene_start_ms and e == params.scene_end_ms ->
          Map.get(demo_scenes, key)

        other ->
          other
      end

    component
    |> put_state(:demo_scenes, demo_scenes)
    |> put_state(:demo_current_scene, demo_current_scene)
    |> put_command(:cast_focus_vote,
      movie_id: params.movie_id,
      scene_start_ms: params.scene_start_ms,
      scene_end_ms: params.scene_end_ms,
      face_id: params.face_id,
      voter_id: params.voter_id
    )
  end

  def action(:focus_vote_updated, params, component) do
    my_session_id = component.state.focus_session_id
    is_mine = params.voter_session_id == my_session_id
    key = scene_key(params.scene_start_ms, params.scene_end_ms)

    old_scene = Map.get(component.state.demo_scenes, key)

    updated_scene =
      old_scene &&
        %{
          old_scene
          | faces:
              old_scene.faces
              |> Enum.map(fn face ->
                votes = Map.get(params.counts, face.id, 0)

                mine? =
                  if is_mine and face.id == params.face_id, do: params.voted?, else: face.mine?

                %{face | votes: votes, mine?: mine?}
              end)
              |> mark_leading()
        }

    demo_scenes =
      if updated_scene,
        do: Map.put(component.state.demo_scenes, key, updated_scene),
        else: component.state.demo_scenes

    demo_current_scene =
      case component.state.demo_current_scene do
        %{start_ms: s, end_ms: e} when s == params.scene_start_ms and e == params.scene_end_ms ->
          updated_scene

        other ->
          other
      end

    component
    |> put_state(:demo_scenes, demo_scenes)
    |> put_state(:demo_current_scene, demo_current_scene)
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
    {counts, _voted_ats, voted?} =
      FocusPoll.toggle_vote(movie_id, scene_start_ms, scene_end_ms, face_id, voter_id)

    put_broadcast(server, {:focus_votes, movie_id}, :focus_vote_updated,
      scene_start_ms: scene_start_ms,
      scene_end_ms: scene_end_ms,
      counts: counts,
      voter_session_id: voter_id,
      face_id: face_id,
      voted?: voted?
    )
  end

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <script>
        {%raw}
        // Same hover-to-pause/resume behavior as the player page focus
        // vote panel (see PlayerPage template): pauses #science-demo-video
        // while the pointer is over #focus-vote-panel and resumes on
        // mouse-out, only if it was playing when the hover started.
        // Delegated from document in the capture phase since
        // mouseenter/mouseleave do not bubble; matches on target being the
        // panel itself so moving between vote buttons inside it does not
        // re-fire. Kept at the top level (not inside the demo modal
        // markup) so it is part of the page initial HTML and the browser
        // actually parses/runs it -- a script tag inserted later by
        // Hologram own client-side DOM patching when the modal opens
        // would not execute.
        (function () {
          if (window.__scienceFocusHoverAttached) { return; }
          window.__scienceFocusHoverAttached = true;

          var wasPlayingBeforeHover = false;

          function setHoverStatus(text) {
            var status = document.getElementById('focus-hover-status');
            if (status) { status.textContent = text; }
          }

          document.addEventListener('mouseenter', function (e) {
            if (!e.target || e.target.id !== 'focus-vote-panel') { return; }
            setHoverStatus('⏸ Paused');
            var video = document.getElementById('science-demo-video');
            if (!video) { return; }
            wasPlayingBeforeHover = !video.paused;
            video.pause();
          }, true);

          document.addEventListener('mouseleave', function (e) {
            if (!e.target || e.target.id !== 'focus-vote-panel') { return; }
            setHoverStatus('▶ Playing');
            var video = document.getElementById('science-demo-video');
            if (video && wasPlayingBeforeHover) { video.play().catch(function () {}); }
          }, true);
        })();
        {/raw}
      </script>

      <div class="max-w-3xl mx-auto">
        <div class="flex items-center justify-center gap-3 mb-1">
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
          <h1 class="font-display text-xl sm:text-3xl text-center">
            The Science Of Celebration Focus
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-6">
          Why your vote creates a smarter highlight reel.
        </p>

        <div class="text-center mb-8">
          <span class="badge badge-lg bg-secondary text-secondary-content border-secondary px-6 py-4">
            The Power Of Visual Attention &amp; Community Consensus
          </span>
        </div>

        <div class="flex flex-col gap-5">
          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <div class="flex items-start gap-4">
                <div class="w-12 h-12 shrink-0 rounded-box bg-primary/10 border-2 border-primary/40 flex items-center justify-center">
                  <span class="hero-eye w-6 h-6 text-primary"></span>
                </div>
                <div>
                  <h2 class="font-display text-base uppercase tracking-wide">The Scientific Importance Of Focus</h2>
                  <p class="text-sm text-base-content/70 mt-2">
                    Scientific research in visual neuroscience proves that human visual processing is highly selective. We naturally foveate — direct our most sensitive part of the retina, the fovea — towards elements that are visually salient, emotionally resonant, or narratively important.
                  </p>
                  <p class="text-sm text-base-content/70 mt-2">
                    In a crowded celebration, identifying who commands visual prominence — the "Focus Winner" — is crucial for understanding a scene's emotional core and reducing cognitive load for the viewer.
                  </p>
                  <p class="text-sm text-base-content/70 mt-2">
                    Studies show that well-focused, prominent individuals lead to clearer expressive communication and stronger emotional recall. Blurry or indistinct scenes create cognitive friction and disengagement. Our platform aims to identify this ground-truth focus, scene by scene — essential for a truly immersive viewing experience.
                  </p>
                </div>
              </div>
              {%if @top_face}
                <div class="mt-4 flex flex-col items-center text-center">
                  <img src={@top_face.thumbnail_url} class="w-20 h-20 sm:w-24 sm:h-24 rounded-full object-cover object-center border-2 border-primary/30" alt="" />
                  <p class="text-xs text-base-content/50 italic mt-2">
                    A moment worth knowing who to focus on — the most-voted face in {@top_face.movie_title}.
                  </p>
                </div>
              {/if}
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <div class="flex items-start gap-4">
                <div class="w-12 h-12 shrink-0 rounded-box bg-primary/10 border-2 border-primary/40 flex items-center justify-center">
                  <span class="hero-cog-6-tooth w-6 h-6 text-primary"></span>
                </div>
                <div>
                  <h2 class="font-display text-base uppercase tracking-wide">The Focus Engine: How We Get You There</h2>
                  <p class="text-sm text-base-content/70 mt-2">
                    Every uploaded film runs through face detection frame by frame, then those detections are clustered into the same handful of unique people who recur throughout it. From there we build a scene timeline — segments where the same set of faces is on screen together. That's as far as the AI goes on its own: it can tell you who's in a scene, but not who the scene is really about. That judgment call is left to real viewers.
                  </p>
                </div>
              </div>
              {%if @leading_faces != []}
                <div class="mt-4 text-center">
                  <div class="flex flex-wrap justify-center gap-4">
                    {%for face <- @leading_faces}
                      <div class="flex flex-col items-center gap-1 w-16">
                        <img src={face.thumbnail_url} class="w-14 h-14 rounded-full object-cover object-center border-2 border-primary/30" alt="" title={face.movie_title} />
                        <span class="text-[0.6rem] text-base-content/50">{face.votes} vote(s)</span>
                      </div>
                    {/for}
                  </div>
                  <p class="text-xs text-base-content/50 italic mt-2">The most-voted face in each film, straight from the Focus Poll.</p>
                </div>
              {/if}
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <div class="flex items-start gap-4">
                <div class="w-12 h-12 shrink-0 rounded-box bg-primary/10 border-2 border-primary/40 flex items-center justify-center">
                  <span class="hero-hand-raised w-6 h-6 text-primary"></span>
                </div>
                <div>
                  <h2 class="font-display text-base uppercase tracking-wide">Your Vote: The Real Signal Powering The Engine</h2>
                  <p class="text-sm text-base-content/70 mt-2">
                    Votes aren't a gimmick — they're the actual ground truth. Anyone watching a scene can vote for whoever they think is its focus, for as many people in that scene as they like, and change their mind by voting again. Once a scene has any votes at all, the face with the most is marked "Leading" — no hidden weighting, no black-box scoring, just what real viewers chose.
                  </p>
                </div>
              </div>
              {%if @demo_seed_scene != nil}
                <div class="mt-4 flex flex-col items-center text-center">
                  <button $click="open_demo" class="btn btn-primary btn-sm gap-2">
                    <span class="hero-play-circle w-5 h-5"></span>
                    Watch This Scene &amp; Vote
                  </button>
                  <p class="text-xs text-base-content/50 italic mt-2">
                    The site's most-voted scene so far ({@demo_seed_scene.time}) — play it and cast a real vote. The panel updates live as the video plays, just like the Premiere Hall player.
                  </p>
                </div>
              {/if}
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <div class="flex items-start gap-4">
                <div class="w-12 h-12 shrink-0 rounded-box bg-primary/10 border-2 border-primary/40 flex items-center justify-center">
                  <span class="hero-scale w-6 h-6 text-primary"></span>
                </div>
                <div>
                  <h2 class="font-display text-base uppercase tracking-wide">Results: Bridging AI And Human Insight</h2>
                  <p class="text-sm text-base-content/70 mt-2">
                    The AI's detection and clustering do the tedious work of knowing who's on screen and when. The community's votes do the part no algorithm can fake: deciding who a moment belongs to. Together they turn hours of raw footage into a film that's genuinely organised around its own best moments — for viewers browsing the Premiere Hall, and for anyone curating a film from Admin View.
                  </p>
                </div>
              </div>
              {%if @demo_leading_face}
                <div class="mt-4 flex flex-col items-center text-center">
                  <div class="relative shrink-0">
                    <img src={@demo_leading_face.thumbnail_url} class="w-20 h-20 sm:w-24 sm:h-24 rounded-full object-cover object-center border-2 border-secondary/40" alt="" />
                    <span class="absolute -top-2 -left-2 badge badge-secondary badge-sm gap-1">🏆 Leading</span>
                  </div>
                  <p class="text-xs text-base-content/50 italic mt-2">
                    The result: {@demo_leading_face.label} is the confirmed focus of the site's most-voted scene.
                  </p>
                </div>
              {/if}
            </div>
          </div>
        </div>

        <div class="mt-8 card card-stock shadow-xl">
          <div class="card-body">
            <h2 class="font-display text-lg text-center">The Focus Engine, Step By Step</h2>
            <div class="gold-divider w-16 mx-auto mb-6 mt-1"></div>

            <div class="flex flex-wrap items-center justify-center gap-2 sm:gap-3">
              {%for {step, index} <- Enum.with_index(@engine_steps)}
                <div class="flex flex-col items-center gap-2 bg-secondary text-secondary-content rounded-box px-3 py-3 w-28 text-center">
                  <span class={"#{step.icon} w-6 h-6"}></span>
                  <span class="font-display text-[0.65rem] tracking-wide uppercase">{step.label}</span>
                </div>
                {%if index < length(@engine_steps) - 1}
                  <span class="text-primary text-xl shrink-0">&rarr;</span>
                {/if}
              {/for}
            </div>
          </div>
        </div>

        <div class="text-center mt-6">
          <Link to={PremierePage} class="btn btn-primary btn-sm">See It In Action</Link>
        </div>
      </div>

      {%if @demo_open && @demo_seed_scene != nil}
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
          <div
            $click_outside="close_demo"
            class="card-stock rounded-box shadow-2xl p-4 w-full max-w-5xl max-h-[90vh] overflow-y-auto"
          >
            <div class="flex justify-between items-center mb-2">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium">The site's most-voted scene</span>
                <span class="badge badge-outline whitespace-nowrap">starts {@demo_seed_scene.time}</span>
              </div>
              <button $click="close_demo" class="btn btn-xs btn-circle btn-ghost">✕</button>
            </div>

            <div class="flex flex-col lg:flex-row gap-4">
              <video
                id="science-demo-video"
                controls
                preload="metadata"
                src={@demo_seed_scene.video_src}
                data-scene-boundaries={@demo_scene_boundaries_json}
                class="w-full lg:w-2/3 aspect-video rounded shrink-0 bg-black"
              ></video>

              <div id="focus-vote-panel" class="lg:w-1/3 lg:max-h-[70vh] lg:overflow-y-auto">
                <h3 class="text-sm font-semibold mb-2">Who's in focus?</h3>
                <div class="flex items-center gap-2 mb-2 flex-wrap">
                  <span class="text-[0.65rem] text-base-content/50">
                    Hover here to pause and vote — move away to resume
                  </span>
                  <span id="focus-hover-status" class="badge badge-outline badge-xs whitespace-nowrap">
                    ▶ Playing
                  </span>
                </div>
                {%if @demo_current_scene == nil}
                  <p class="text-sm text-base-content/60">No one recognised at this point in the video.</p>
                {%else}
                  <div class="flex items-center gap-2 mb-2">
                    <span class="badge badge-outline whitespace-nowrap">{@demo_current_scene.time}</span>
                    <span class="text-xs text-base-content/60">Vote live for who's on screen</span>
                  </div>
                  {%if @demo_current_scene.faces == []}
                    <p class="text-sm text-base-content/60">No one recognised at this point in the video.</p>
                  {%else}
                    <div class="flex flex-wrap gap-2">
                      {%for face <- @demo_current_scene.faces}
                        <button
                          $click={:demo_focus_vote_clicked, movie_id: @demo_movie_id, scene_start_ms: @demo_current_scene.start_ms, scene_end_ms: @demo_current_scene.end_ms, face_id: face.id, voter_id: @focus_session_id}
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
                {/if}
              </div>
            </div>
          </div>
        </div>
      {/if}
    </div>
    """
  end
end
