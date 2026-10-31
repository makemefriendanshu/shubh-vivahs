defmodule ShubhVivahsWeb.Hologram.Pages.AdminMoviePage do
  @moduledoc """
  Per-movie scene browser: the movie's scene timeline (who's on screen,
  segmented every time that changes), plus every unique face recognised
  in it with a thumbnail and its own timestamp ranges.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias ShubhVivahs.Accounts
  alias ShubhVivahs.FaceDetection
  alias ShubhVivahs.FaceDetection.{Movie, SceneIndex}
  alias ShubhVivahs.MovieJobRunner
  alias ShubhVivahs.MovieJobs
  alias ShubhVivahs.QualityVersions
  alias ShubhVivahs.FocusPoll
  alias ShubhVivahs.Repo
  alias ShubhVivahs.VideoMetadata
  alias ShubhVivahs.VideoPreview
  alias ShubhVivahs.VideoSegments
  alias ShubhVivahsWeb.Hologram.Middleware.RequireSuperuser
  alias ShubhVivahsWeb.Hologram.Pages.AdminMoviesPage

  # /admin/<uploader>/<slug> — see ShubhVivahs.MovieSlug. Older
  # /admin/movies/<id> and /admin/movies/<uploader>/<slug> links redirect
  # here (PlayerUrlRedirect, LegacyAdminMoviePage).
  route "/admin/:uploader/:name"

  middleware RequireSuperuser
  middleware ShubhVivahsWeb.Hologram.Middleware.PlayerUrlRedirect, mode: :admin
  param :uploader, :string
  param :name, :string

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  @bucket_ms 5 * 60 * 1000

  def init(params, component, server) do
    movie_record = ShubhVivahs.MovieSlug.get(params.name)
    preloaded = movie_record && Repo.preload(movie_record, faces: :detections)
    focus_session_id = Ecto.UUID.generate()

    votes_by_scene = if movie_record, do: scene_votes_by_key(movie_record.id), else: %{}

    scenes_list =
      if preloaded, do: movie_scenes(preloaded, votes_by_scene, focus_session_id), else: []

    scenes_by_key = Map.new(scenes_list, &{scene_key(&1), &1})

    # How many scenes (as listed in the Scenes section) each face is in.
    scene_counts =
      scenes_list
      |> Enum.flat_map(fn scene -> Enum.map(scene.faces, & &1.id) end)
      |> Enum.frequencies()

    # Every vote, per face, as {scene start, votes}: attributed to the
    # face's on-screen stretches in face_summary/3.
    voted_scenes =
      for scene <- scenes_list, face <- scene.faces, face.votes > 0, reduce: %{} do
        acc ->
          Map.update(
            acc,
            face.id,
            [{scene.start_ms, face.votes}],
            &[{scene.start_ms, face.votes} | &1]
          )
      end

    faces =
      if preloaded,
        do:
          preloaded.faces
          |> Enum.map(&face_summary(&1, voted_scenes, scene_counts))
          |> sort_faces(:votes),
        else: []

    movie = movie_record && build_movie(movie_record)

    label_drafts =
      Map.new(faces, fn face ->
        {face.id, %{label: face.label || "", subtitle: face.subtitle || ""}}
      end)

    component =
      component
      |> put_state(:movie, movie)
      |> put_state(:focus_session_id, focus_session_id)
      |> put_state(:faces, faces)
      |> put_state(:face_count, length(faces))
      |> put_state(:named_face_count, Enum.count(faces, &named?/1))
      |> put_state(:face_sort_options, [
        %{key: :votes, label: "Most voted"},
        %{key: :appearances, label: "Most scenes"},
        %{key: :named, label: "Named first"},
        %{key: :unnamed, label: "Unnamed first"}
      ])
      |> put_state(:scenes, scenes_by_key)
      |> put_state(:scene_buckets, scene_buckets(scenes_list))
      |> put_state(:scene_count, length(scenes_list))
      |> put_state(:scene_boundaries_json, scene_boundaries_json(scenes_list))
      |> put_state(:current_preview_scene, nil)
      |> put_state(:scene_open, false)
      |> put_state(:label_drafts, label_drafts)
      |> put_state(:title_draft, (movie && movie.title) || "")
      |> put_state(:description_draft, (movie && movie.description) || "")
      |> put_state(:event_date_draft, (movie && movie.event_date_input) || "")
      |> put_state(:location_draft, (movie && movie.location) || "")
      |> put_state(:recognition_confirm, false)
      |> put_state(:job_message, nil)
      |> put_state(:jobs, movie_record && jobs_view(movie_record))
      |> put_state(:polling?, false)

    # Keep the progress bars moving if a job is already running.
    component =
      if movie_record && any_running?(component.state.jobs),
        do:
          component
          |> put_state(:polling?, true)
          |> put_action(name: :poll_jobs, params: %{}, delay: 3000),
        else: component

    server = if movie, do: put_subscription(server, {:focus_votes, movie.id}), else: server
    # MovieJobRunner broadcasts :movies_updated when a job it ran ends.
    server = put_subscription(server, :movies_changed)

    {component, server}
  end

  # "Run face recognition" / "Generate quality versions" buttons (see
  # MovieJobRunner). Re-running recognition replaces every face, which
  # cascades to their names and focus votes, so when there are faces it
  # asks first (:recognition_clicked -> confirm row -> :run_recognition).
  def action(:recognition_clicked, _params, component) do
    if component.state.face_count > 0 do
      put_state(component, recognition_confirm: true, job_message: nil)
    else
      start_job(component, "recognition")
    end
  end

  def action(:run_recognition, _params, component), do: start_job(component, "recognition")

  def action(:cancel_recognition, _params, component) do
    put_state(component, :recognition_confirm, false)
  end

  def action(:run_versions, _params, component), do: start_job(component, "versions")

  # Progress bars: jobs can run in another OS process (a `mix` task) that
  # can't push to this page, so while anything is running the page polls
  # every 3s. :movies_updated (a server-run job ending) refreshes once.
  def action(:poll_jobs, _params, component) do
    put_command(component, :refresh_jobs, movie_id: component.state.movie.id, from_poll: true)
  end

  def action(:movies_updated, _params, component) do
    if component.state.movie do
      put_command(component, :refresh_jobs, movie_id: component.state.movie.id, from_poll: false)
    else
      component
    end
  end

  def action(:jobs_refreshed, params, component) do
    finished_recognition? =
      component.state.jobs.recognition.running? and not params.jobs.recognition.running? and
        params.movie.status == "done"

    if finished_recognition? do
      # New faces and scenes: reload rather than rebuild all of init/3 here.
      JS.exec("window.location.reload();")
      component
    else
      component =
        put_state(component,
          movie: params.movie,
          jobs: params.jobs,
          job_message: Map.get(params, :message),
          recognition_confirm: false
        )

      running? = any_running?(params.jobs)

      cond do
        running? and (params.from_poll or not component.state.polling?) ->
          component
          |> put_state(:polling?, true)
          |> put_action(name: :poll_jobs, params: %{}, delay: 3000)

        not running? and params.from_poll ->
          put_state(component, :polling?, false)

        true ->
          component
      end
    end
  end

  # find_scene_at/2 below is an O(total_scenes) scan — fine server-side
  # (see :show_scene the command, below) but a movie with a couple thousand
  # scenes (long movies sampled at ~1fps) blew the JS call stack when this
  # ran as a client-side action, since Hologram's client Enum isn't
  # tail-call-optimized. Same class of problem the comments on
  # update_face_focus/5 and update_scene_bucket/3 already call out and
  # avoid — this one spot was missed. So this action only opens the modal
  # and hands the actual lookup to a command; :scene_shown (below) fills
  # in the scene once that resolves.
  def action(:show_scene, params, component) do
    component
    |> put_state(:scene_open, true)
    |> put_state(:current_preview_scene, nil)
    |> put_command(:show_scene,
      movie_id: params.movie_id,
      start_ms: params.start_ms,
      end_ms: params.end_ms,
      focus_session_id: component.state.focus_session_id
    )
  end

  def action(:scene_shown, params, component) do
    component
    |> put_state(:current_preview_scene, params.scene)
    |> put_action(name: :play_scene_video, params: %{src: params.src}, delay: 0)
  end

  # The <video> has no `src` in the template at all — it's set here via
  # JS, not as a static attribute (that made the browser start its own
  # implicit fetch on mount, racing an explicit play() call). Calling
  # play() immediately after setting src turned out to still race the
  # browser's own resource-selection for the new source (the same
  # AbortException, just moved) — waiting for `loadedmetadata` before
  # calling play() is what actually settles it.
  #
  # Plays forward past the clicked scene rather than auto-pausing at its
  # end (the old behavior, back when this was a fire-and-forget preview
  # clip) — same `data-scene-boundaries` + polling-driven scene tracking
  # PlayerPage uses, so "Who's in focus?" keeps following along and stays
  # votable as playback continues, instead of freezing on the one scene
  # that was clicked.
  def action(:play_scene_video, params, component) do
    JS.exec("""
    const video = document.getElementById('scene-video');
    if (video) {
      video.pause();
      video.muted = true;
      video.src = #{inspect(params.src)};

      video.addEventListener('loadedmetadata', () => {
        video.play().catch((err) => console.warn('scene preview: play() rejected:', err));
      }, { once: true });
    }

    (function () {
      if (window.__adminPreviewInterval) { clearInterval(window.__adminPreviewInterval); }

      var scenes = null;
      var staleToleranceMs = 5000;
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

      window.__adminPreviewInterval = setInterval(function () {
        var video = document.getElementById('scene-video');
        if (!video) {
          clearInterval(window.__adminPreviewInterval);
          window.__adminPreviewInterval = null;
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
          Hologram.dispatchAction('preview_scene_changed', 'page', { scene_key: key });
        }
      }, 200);
    })();
    """)

    component
  end

  # Dispatched only when the resolved scene key actually changes (see the
  # polling loop in :play_scene_video above) — an O(1) Map lookup into
  # the same @scenes map :show_scene already uses, rather than a scan
  # through every scene on each tick.
  def action(:preview_scene_changed, params, component) do
    scene = Map.get(component.state.scenes, params.scene_key)
    put_state(component, :current_preview_scene, scene)
  end

  def action(:close_player, _params, component) do
    JS.exec("""
    const video = document.getElementById('scene-video');
    if (video) { video.pause(); }
    if (window.__adminPreviewInterval) {
      clearInterval(window.__adminPreviewInterval);
      window.__adminPreviewInterval = null;
    }
    """)

    put_state(component, :scene_open, false)
  end

  # These edit panels used to be plain <form method="post" $submit={...}>
  # elements with a type="submit" button — standard Hologram form
  # handling. On this page that reliably failed in production: the native
  # browser form submission would go through instead of Hologram's client
  # JS intercepting it, and since Hologram's router treats any unmatched
  # request (GET or POST) as a fresh page load (see Hologram.Router's
  # catch-all `match _`), a real POST to this route just silently
  # re-rendered the page from scratch, discarding the edit — "page
  # reloads but edit fails", with no error anywhere to explain why. $click
  # on a plain (non-submit) button sidesteps the browser's native form
  # submission entirely, the same way the scene-preview and focus-vote
  # clicks elsewhere on this page already do, so there is no native
  # fallback path left for the browser to take. Each field's current text
  # is tracked in state via $change (see the *_draft state below) since a
  # plain $click handler has no event payload of its own to read it from.
  def action(:update_title_draft, params, component) do
    put_state(component, :title_draft, params.event.value)
  end

  def action(:save_movie_title, _params, component) do
    title = blank_to_nil(component.state.title_draft)
    put_command(component, :persist_movie_title, movie_id: component.state.movie.id, title: title)
  end

  def action(:movie_title_saved, params, component) do
    JS.exec("""
    const details = document.getElementById('rename-movie-details');
    if (details) { details.open = false; }
    """)

    component
    |> put_state(:movie, %{component.state.movie | title: params.title})
    |> put_state(:title_draft, params.title)
  end

  def action(:update_description_draft, params, component) do
    put_state(component, :description_draft, params.event.value)
  end

  def action(:update_event_date_draft, params, component) do
    put_state(component, :event_date_draft, params.event.value)
  end

  def action(:update_location_draft, params, component) do
    put_state(component, :location_draft, params.event.value)
  end

  def action(:save_movie_details, _params, component) do
    put_command(component, :persist_movie_details,
      movie_id: component.state.movie.id,
      description: blank_to_nil(component.state.description_draft),
      event_date: blank_to_nil(component.state.event_date_draft),
      location: blank_to_nil(component.state.location_draft)
    )
  end

  def action(:movie_details_saved, params, component) do
    JS.exec("""
    const details = document.getElementById('listing-details-details');
    if (details) { details.open = false; }
    """)

    movie = %{
      component.state.movie
      | description: params.description,
        event_date_input: params.event_date_input,
        location: params.location
    }

    component
    |> put_state(:movie, movie)
    |> put_state(:description_draft, params.description || "")
    |> put_state(:event_date_draft, params.event_date_input)
    |> put_state(:location_draft, params.location || "")
  end

  def action(:update_label_draft, params, component) do
    put_state(
      component,
      :label_drafts,
      put_draft_field(component, params.face_id, :label, params.event.value)
    )
  end

  def action(:update_subtitle_draft, params, component) do
    put_state(
      component,
      :label_drafts,
      put_draft_field(component, params.face_id, :subtitle, params.event.value)
    )
  end

  def action(:save_label, params, component) do
    draft = Map.get(component.state.label_drafts, params.face_id, %{label: "", subtitle: ""})

    put_command(component, :persist_label,
      face_id: params.face_id,
      label: blank_to_nil(draft.label),
      subtitle: blank_to_nil(draft.subtitle)
    )
  end

  def action(:label_saved, params, component) do
    JS.exec("""
    const details = document.getElementById('label-details-#{params.face_id}');
    if (details) { details.open = false; }
    """)

    faces =
      Enum.map(component.state.faces, fn face ->
        if face.id == params.face_id do
          %{face | label: params.label, subtitle: params.subtitle}
        else
          face
        end
      end)

    label_drafts =
      Map.put(component.state.label_drafts, params.face_id, %{
        label: params.label || "",
        subtitle: params.subtitle || ""
      })

    component
    |> put_state(:faces, faces)
    |> put_state(:named_face_count, Enum.count(faces, &named?/1))
    |> put_state(:label_drafts, label_drafts)
  end

  # Flips the clicked face's vote/count in the live preview panel right
  # away, mirroring the toggle the :cast_focus_vote command will perform
  # server-side, instead of leaving the button looking unresponsive until
  # the broadcast round trip lands. Only the panel the voter is actually
  # looking at is updated optimistically here (not scene_buckets or the
  # all-recognised-faces grid, both hidden behind the modal anyway) —
  # :focus_vote_updated below still lands moments later and reconciles
  # everything, including this guess, with the authoritative counts.
  def action(:focus_vote_clicked, params, component) do
    key = scene_key(params.scene_start_ms, params.scene_end_ms)

    scenes =
      Map.update!(component.state.scenes, key, fn scene ->
        faces =
          Enum.map(scene.faces, fn face ->
            if face.id == params.face_id do
              now_mine? = !face.mine?
              %{face | mine?: now_mine?, votes: face.votes + if(now_mine?, do: 1, else: -1)}
            else
              face
            end
          end)

        %{scene | faces: faces}
      end)

    current_preview_scene =
      case component.state.current_preview_scene do
        %{start_ms: s, end_ms: e} when s == params.scene_start_ms and e == params.scene_end_ms ->
          Map.get(scenes, key)

        other ->
          other
      end

    component
    |> put_state(:scenes, scenes)
    |> put_state(:current_preview_scene, current_preview_scene)
    |> put_command(:cast_focus_vote,
      movie_id: params.movie_id,
      scene_start_ms: params.scene_start_ms,
      scene_end_ms: params.scene_end_ms,
      face_id: params.face_id,
      voter_id: params.voter_id
    )
  end

  # A movie can have thousands of detections and hundreds of scenes (see
  # SceneIndex.scenes/1), and this action runs on the client — rebuilding
  # every derived structure (scene_buckets, every face's totals) from the
  # full scene list on each vote made the client's interpreter visibly
  # freeze for a moment on every click. Instead this only touches the one
  # scene that changed and, for the voting face, applies the vote-count
  # delta directly to the movie-wide total and to whichever of that face's
  # own timestamp ranges overlap the changed scene, rather than a full
  # re-sum.
  def action(:focus_vote_updated, params, component) do
    my_session_id = component.state.focus_session_id
    is_mine = params.voter_session_id == my_session_id
    key = scene_key(params.scene_start_ms, params.scene_end_ms)

    old_scene = Map.fetch!(component.state.scenes, key)
    old_votes_in_scene = old_scene.faces |> Enum.find(&(&1.id == params.face_id)) |> face_votes()
    new_votes_in_scene = Map.get(params.counts, params.face_id, 0)

    updated_faces =
      Enum.map(old_scene.faces, fn face ->
        votes = Map.get(params.counts, face.id, 0)

        mine? =
          if is_mine and face.id == params.face_id, do: params.voted?, else: face.mine?

        voted_ats = params.voted_ats |> Map.get(face.id, []) |> Enum.map(&format_timestamp/1)

        %{face | votes: votes, mine?: mine?, voted: votes > 0, voted_ats: voted_ats}
      end)

    updated_scene = %{
      old_scene
      | faces: updated_faces,
        voted: Enum.any?(updated_faces, & &1.voted)
    }

    scenes = Map.put(component.state.scenes, key, updated_scene)

    current_preview_scene =
      case component.state.current_preview_scene do
        %{start_ms: s, end_ms: e} when s == params.scene_start_ms and e == params.scene_end_ms ->
          updated_scene

        other ->
          other
      end

    faces =
      component.state.faces
      |> update_face_focus(
        scenes,
        old_scene,
        params.face_id,
        new_votes_in_scene - old_votes_in_scene
      )

    component
    |> put_state(:scenes, scenes)
    |> put_state(:current_preview_scene, current_preview_scene)
    |> put_state(
      :scene_buckets,
      update_scene_bucket(component.state.scene_buckets, key, updated_scene)
    )
    |> put_state(:faces, faces)
  end

  defp face_votes(nil), do: 0
  defp face_votes(face), do: face.votes

  # Which bucket holds the changed scene is known outright from its
  # start_ms (see scene_buckets/1's bucketing), so this only needs to find
  # that one bucket by its (O(1)-comparable) index rather than scanning
  # every bucket's full scene list with Enum.any? just to rule it out —
  # each such scan visibly added up in Hologram's client-side interpreter.
  defp update_scene_bucket(scene_buckets, key, updated_scene) do
    target_index = div(updated_scene.start_ms, @bucket_ms)

    Enum.map(scene_buckets, fn bucket ->
      if bucket.index == target_index do
        scenes = Enum.map(bucket.scenes, &if(scene_key(&1) == key, do: updated_scene, else: &1))
        %{bucket | scenes: scenes}
      else
        bucket
      end
    end)
  end

  # Live counterpart of face_summary/3: a vote on a scene goes to the
  # stretch (time pill) that scene falls in (range_index_for/2), and the
  # face total is re-summed from the pills so the two always agree. Runs
  # client-side on every vote, so it touches one face and does one linear
  # pass over its stretches.
  defp update_face_focus(faces, _scenes, changed_scene, face_id, delta) do
    faces
    |> Enum.map(fn face ->
      if face.id == face_id do
        target = range_index_for(face.scenes, changed_scene.start_ms)

        ranges =
          face.scenes
          |> Enum.with_index()
          |> Enum.map(fn {range, index} ->
            if index == target do
              votes = range.votes + delta
              %{range | votes: votes, voted: votes > 0}
            else
              range
            end
          end)

        focus_votes = ranges |> Enum.map(& &1.votes) |> Enum.sum()
        %{face | scenes: ranges, focus_votes: focus_votes, voted: focus_votes > 0}
      else
        face
      end
    end)
  end

  # Index of the stretch (time pill) a scene starting at `at_ms` belongs
  # to: the one containing it, else the nearest, since scene and stretch
  # edges come from slightly different merging. A plain reduce so it also
  # runs client-side in Hologram.
  defp range_index_for(ranges, at_ms) do
    {_distance, index} =
      ranges
      |> Enum.with_index()
      |> Enum.reduce({nil, nil}, fn {range, index}, {best_distance, best_index} ->
        distance =
          cond do
            at_ms < range.start_ms -> range.start_ms - at_ms
            at_ms > range.end_ms -> at_ms - range.end_ms
            true -> 0
          end

        if is_nil(best_distance) or distance < best_distance,
          do: {distance, index},
          else: {best_distance, best_index}
      end)

    index
  end

  # The heavy end of :show_scene (see the action above): rebuilds the same
  # scenes list init/3 computes and runs find_scene_at/2 against it, but
  # here on the server — real BEAM recursion, not Hologram's client
  # interpreter, so a movie with thousands of scenes doesn't blow the stack.
  def command(:show_scene, params, server) do
    start_seconds = div(params.start_ms, 1000)

    # Only a start point in the media fragment, no end — some browsers
    # honor a temporal fragment's end by stopping there natively, which
    # would fight the now-continuous playback (see :play_scene_video).
    src = "/premiere/videos/#{params.movie_id}#t=#{start_seconds}"

    preloaded = Movie |> Repo.get!(params.movie_id) |> Repo.preload(faces: :detections)
    votes_by_scene = scene_votes_by_key(params.movie_id)
    scenes_list = movie_scenes(preloaded, votes_by_scene, params.focus_session_id)
    scene = find_scene_at(scenes_list, params.start_ms)

    put_action(server, :scene_shown, scene: scene, src: src)
  end

  def command(:start_job, %{movie_id: movie_id, kind: kind}, server) do
    # Defense in depth: the page is superuser-only, but commands are their
    # own requests.
    message =
      if superuser?(server) do
        case MovieJobRunner.start(movie_id, kind) do
          :ok ->
            nil

          {:error, :already_running} ->
            "That's already running for this video."

          {:error, :busy} ->
            "Another job is running on the server right now — try again when it's done."

          {:error, :not_found} ->
            "This video no longer exists."
        end
      else
        "Only admins can run this."
      end

    refresh_jobs(server, movie_id, false, message)
  end

  def command(:refresh_jobs, %{movie_id: movie_id, from_poll: from_poll}, server) do
    refresh_jobs(server, movie_id, from_poll, nil)
  end

  def command(:persist_label, params, server) do
    {:ok, _face} =
      FaceDetection.label_face(params.face_id, %{label: params.label, subtitle: params.subtitle})

    put_action(server, :label_saved,
      face_id: params.face_id,
      label: params.label,
      subtitle: params.subtitle
    )
  end

  def command(:persist_movie_title, params, server) do
    {:ok, movie} = FaceDetection.rename_movie(params.movie_id, params.title)

    put_action(server, :movie_title_saved,
      movie_id: params.movie_id,
      title: movie.title || movie.path
    )
  end

  def command(:persist_movie_details, params, server) do
    {:ok, movie} =
      FaceDetection.update_movie_details(params.movie_id, %{
        description: params.description,
        event_date: params.event_date,
        location: params.location
      })

    put_action(server, :movie_details_saved,
      description: movie.description,
      event_date_input: date_to_input(movie.event_date),
      location: movie.location
    )
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

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp put_draft_field(component, face_id, field, value) do
    draft = Map.get(component.state.label_drafts, face_id, %{label: "", subtitle: ""})
    Map.put(component.state.label_drafts, face_id, Map.put(draft, field, value))
  end

  # Matches the key the "Who's in focus?" panel looks scenes up by (see
  # PlayerPage) — an O(1) Map lookup when a scene preview is opened or a
  # focus-vote broadcast comes in, rather than a scan through every scene.
  defp scene_key(%{start_ms: start_ms, end_ms: end_ms}), do: "#{start_ms}:#{end_ms}"
  defp scene_key(start_ms, end_ms), do: "#{start_ms}:#{end_ms}"

  # The "Scenes" grid's timestamps come straight from the "who's on screen
  # together" scenes and match a scenes-map key exactly, but a face's own
  # timestamp badges under "All recognised faces" come from that face's
  # continuous-appearance ranges (SceneIndex.ranges/1) — a different
  # segmentation that rarely shares boundaries with the former, so an exact
  # key lookup misses and the voting panel silently doesn't appear. Since
  # the "who's on screen together" scenes fully partition the timeline with
  # no gaps, the last one starting at or before `ms` is always the scene
  # actually playing at that instant, regardless of which grid it was
  # clicked from. Also the single source of truth for which scene "owns" a
  # given point in time: clicking a time pill opens the scene playing at
  # the start of that stretch.
  defp find_scene_at(scenes, ms) do
    scenes
    |> scene_values()
    |> Enum.filter(&(&1.start_ms <= ms))
    |> Enum.max_by(& &1.start_ms, fn -> nil end)
  end

  defp scene_values(scenes) when is_map(scenes), do: Map.values(scenes)
  defp scene_values(scenes) when is_list(scenes), do: scenes

  # Only start/end timestamps — enough for the client-side JS to figure
  # out which scene index is current as the preview keeps playing, same
  # as PlayerPage's own scene_boundaries_json/1.
  defp scene_boundaries_json(scenes) do
    scenes
    |> Enum.map(&%{start_ms: &1.start_ms, end_ms: &1.end_ms})
    |> Jason.encode!()
  end

  defp scene_votes_by_key(movie_id) do
    movie_id
    |> FocusPoll.all_votes()
    |> Enum.group_by(&{&1.scene_start_ms, &1.scene_end_ms})
  end

  defp movie_scenes(preloaded_movie, votes_by_scene, session_id) do
    face_labels = Map.new(preloaded_movie.faces, fn face -> {face.id, face.label} end)

    preloaded_movie.faces
    |> Enum.flat_map(& &1.detections)
    |> SceneIndex.scenes()
    |> Enum.map(fn scene ->
      scene_votes = Map.get(votes_by_scene, {scene.start_ms, scene.end_ms}, [])
      votes_by_face = Enum.group_by(scene_votes, & &1.face_id)

      my_voted_faces =
        scene_votes |> Enum.filter(&(&1.session_id == session_id)) |> MapSet.new(& &1.face_id)

      faces =
        Enum.map(scene.face_ids, fn face_id ->
          face_votes = Map.get(votes_by_face, face_id, [])

          %{
            id: face_id,
            label: Map.get(face_labels, face_id) || "Face ##{face_id}",
            votes: length(face_votes),
            mine?: MapSet.member?(my_voted_faces, face_id),
            voted: face_votes != [],
            voted_ats: face_votes |> voted_ats() |> Enum.map(&format_timestamp/1)
          }
        end)

      %{
        time: format_scene(scene),
        start_ms: scene.start_ms,
        end_ms: scene.end_ms,
        faces: faces,
        voted: Enum.any?(faces, & &1.voted)
      }
    end)
  end

  defp scene_buckets(scenes_list) do
    scenes_list
    |> Enum.sort_by(& &1.start_ms)
    |> Enum.group_by(fn scene -> div(scene.start_ms, @bucket_ms) end)
    |> Enum.sort_by(fn {bucket_index, _scenes} -> bucket_index end)
    |> Enum.map(fn {bucket_index, scenes} ->
      %{
        index: bucket_index,
        label:
          "#{format_time(bucket_index * @bucket_ms)}–#{format_time((bucket_index + 1) * @bucket_ms)}",
        scene_count: length(scenes),
        scenes: scenes
      }
    end)
  end

  defp build_movie(movie) do
    %{
      id: movie.id,
      slug: ShubhVivahs.MovieSlug.ensure(movie).slug,
      uploader_slug: ShubhVivahs.MovieSlug.uploader_slug(movie),
      title: movie.title || movie.path,
      status: movie.status,
      description: movie.description,
      event_date_input: date_to_input(movie.event_date),
      location: movie.location,
      thumbnail_url: "/premiere/videos/#{movie.id}/thumbnail.jpg",
      # /gallery/… or /library/…, whichever the movie belongs to.
      player_path: ShubhVivahs.MovieSlug.path(movie)
    }
  end

  defp date_to_input(nil), do: ""
  defp date_to_input(%Date{} = date), do: Date.to_iso8601(date)

  defp face_summary(face, voted_scenes, scene_counts) do
    ranges = SceneIndex.ranges(face.detections)

    # A face is on screen through many scenes (others come and go), so each
    # of its stretches (a time pill) collects the votes of every scene that
    # starts inside it. Counting only the scene that starts with the
    # stretch, as this used to, dropped most votes from the totals.
    votes_by_range =
      voted_scenes
      |> Map.get(face.id, [])
      |> Enum.reduce(%{}, fn {start_ms, votes}, acc ->
        Map.update(acc, range_index_for(ranges, start_ms), votes, &(&1 + votes))
      end)

    scenes =
      ranges
      |> Enum.with_index()
      |> Enum.map(fn {range, index} ->
        votes = Map.get(votes_by_range, index, 0)

        %{
          time: format_scene(range),
          start_ms: range.start_ms,
          end_ms: range.end_ms,
          votes: votes,
          voted: votes > 0
        }
      end)

    # The sum of the pills above, which together hold every vote cast for
    # this face (each voted scene lands in exactly one stretch), so this
    # matches FocusPoll's per-face total.
    focus_votes = scenes |> Enum.map(& &1.votes) |> Enum.sum()

    %{
      id: face.id,
      label: face.label,
      subtitle: face.subtitle,
      scenes: scenes,
      scene_count: Map.get(scene_counts, face.id, 0),
      focus_votes: focus_votes,
      voted: focus_votes > 0
    }
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

  # Initial (server-side) order: most voted, then most scenes. The sort
  # buttons reorder the cards in the browser instead (see the script in the
  # template), because any Hologram action on this page is slow: its state
  # holds every scene and face.
  defp sort_faces(faces, :votes),
    do: Enum.sort_by(faces, &(&1.focus_votes * 1_000_000 + &1.scene_count), :desc)

  defp named?(face), do: is_binary(face.label) and face.label != ""

  defp start_job(component, kind) do
    component
    |> put_state(recognition_confirm: false, job_message: nil)
    |> put_command(:start_job, movie_id: component.state.movie.id, kind: kind)
  end

  defp any_running?(nil), do: false
  defp any_running?(jobs), do: jobs.recognition.running? or jobs.versions.running?

  defp refresh_jobs(server, movie_id, from_poll, message) do
    case Repo.get(Movie, movie_id) do
      nil ->
        server

      movie ->
        put_action(server, :jobs_refreshed,
          movie: build_movie(movie),
          jobs: jobs_view(movie),
          from_poll: from_poll,
          message: message
        )
    end
  end

  # Plain maps for the two job panels. Recognition's "running" comes from
  # the movie's own status (what every ingest path sets), its progress
  # from MovieJobs; a run whose process died without saying so shows as
  # stalled and can be started again.
  defp jobs_view(movie) do
    recognition_job = MovieJobs.get(movie.id, "recognition")
    versions_job = MovieJobs.get(movie.id, "versions")

    recognition_state =
      cond do
        movie.status == "processing" and MovieJobs.stalled?(recognition_job) -> :stalled
        movie.status == "processing" -> :running
        movie.status == "done" -> :done
        movie.status == "failed" -> :failed
        true -> :not_run
      end

    versions_state =
      case versions_job do
        nil -> :not_run
        job -> if MovieJobs.stalled?(job), do: :stalled, else: String.to_existing_atom(job.status)
      end

    %{
      recognition: job_panel(recognition_state, recognition_job),
      versions:
        job_panel(versions_state, versions_job)
        |> Map.put(:outputs, version_outputs(movie))
    }
  end

  defp job_panel(state, job) do
    %{
      running?: state == :running,
      stalled?: state == :stalled,
      label: job_label(state),
      badge_class: job_badge_class(state),
      stage: job && job.stage,
      percent: job && state == :running && job.progress && round(job.progress * 100),
      eta: job && state == :running && format_eta(MovieJobs.seconds_left(job)),
      error: job && state == :failed && job.message
    }
  end

  defp job_label(:running), do: "Running"
  defp job_label(:stalled), do: "Stalled"
  defp job_label(:done), do: "Done"
  defp job_label(:failed), do: "Failed"
  defp job_label(:not_run), do: "Not run yet"

  defp job_badge_class(:running), do: "badge badge-sm badge-info"
  defp job_badge_class(:stalled), do: "badge badge-sm badge-warning"
  defp job_badge_class(:done), do: "badge badge-sm badge-success"
  defp job_badge_class(:failed), do: "badge badge-sm badge-error"
  defp job_badge_class(:not_run), do: "badge badge-sm badge-ghost"

  defp format_eta(nil), do: nil
  defp format_eta(seconds) when seconds < 60, do: "under a minute left"
  defp format_eta(seconds) when seconds < 3600, do: "about #{div(seconds, 60)} min left"

  defp format_eta(seconds),
    do: "about #{div(seconds, 3600)} h #{div(rem(seconds, 3600), 60)} min left"

  # What the player's quality picker and download menu can offer now.
  defp version_outputs(movie) do
    source = VideoMetadata.fetch(movie)

    preview =
      cond do
        VideoPreview.preview_ready?(movie) -> output_detail(VideoMetadata.fetch_preview(movie))
        QualityVersions.preview_worthwhile?(movie) -> nil
        true -> "not needed — original is already 720p or smaller"
      end

    minimal =
      if VideoPreview.minimal_ready?(movie), do: output_detail(VideoMetadata.fetch_minimal(movie))

    parts =
      ["source", "preview", "minimal"]
      |> Enum.map(&length(VideoSegments.list(movie, &1)))
      |> Enum.reject(&(&1 == 0))

    [
      %{key: "original", label: "Original", detail: output_detail(source), ready?: true},
      %{
        key: "preview",
        label: "720p data saver",
        detail: preview,
        ready?: VideoPreview.preview_ready?(movie)
      },
      %{key: "minimal", label: "360p minimal", detail: minimal, ready?: minimal != nil},
      %{
        key: "parts",
        label: "Download parts",
        detail:
          if(parts != [], do: "#{length(parts)} quality level(s), ~#{hd(parts)} parts each"),
        ready?: parts != []
      }
    ]
  end

  defp output_detail(nil), do: nil
  defp output_detail(metadata), do: VideoMetadata.describe_quality(metadata)

  defp superuser?(server) do
    case server.user_id && Accounts.get_user(server.user_id) do
      %Accounts.User{} = user -> Accounts.superuser?(user)
      _ -> false
    end
  end

  # The Scenes and All recognised faces sections, and each 5-minute scene
  # block, are <details> accordions whose headers stick while their content
  # scrolls past (the block header sits under the Scenes header: its
  # top-16/sm:top-14 matches the section header's h-16/sm:h-14; on phones
  # the header stacks title over count, and "All recognised faces" is
  # shortened to "Faces", so the title isn't cut off — the site's large
  # root font leaves a 390px phone ~200px for it). No overflow-hidden/inner scroll boxes on
  # them, which would stop the headers sticking.
  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <div class="max-w-4xl mx-auto">
        <Link to={AdminMoviesPage} class="link link-hover text-sm">&larr; Back to admin</Link>

        {%if @movie == nil}
          <div class="card card-stock shadow-xl mt-4">
            <div class="card-body">
              <p class="text-base-content/70">This film could not be found.</p>
            </div>
          </div>
        {%else}
          <script>
            {%raw}
            // Same hover-to-pause/resume behavior as the player page focus
            // vote panel (see PlayerPage template): pauses #scene-video
            // while the pointer is over #focus-vote-panel and resumes on
            // mouse-out, only if it was playing when the hover started.
            // Delegated from document in the capture phase since
            // mouseenter/mouseleave do not bubble; matches on target being
            // the panel itself so moving between vote buttons inside it
            // does not re-fire. Kept at the top level (not inside the
            // scene-preview modal markup) so it is part of the page initial
            // HTML and the browser actually parses/runs it -- a script tag
            // inserted later by Hologram own client-side DOM patching when
            // the modal opens would not execute.
            (function () {
              if (window.__adminFocusHoverAttached) { return; }
              window.__adminFocusHoverAttached = true;

              var wasPlayingBeforeHover = false;

              function setHoverStatus(text) {
                var status = document.getElementById('focus-hover-status');
                if (status) { status.textContent = text; }
              }

              document.addEventListener('mouseenter', function (e) {
                if (!e.target || e.target.id !== 'focus-vote-panel') { return; }
                setHoverStatus('⏸ Paused');
                var video = document.getElementById('scene-video');
                if (!video) { return; }
                wasPlayingBeforeHover = !video.paused;
                video.pause();
              }, true);

              document.addEventListener('mouseleave', function (e) {
                if (!e.target || e.target.id !== 'focus-vote-panel') { return; }
                setHoverStatus('▶ Playing');
                var video = document.getElementById('scene-video');
                if (video && wasPlayingBeforeHover) { video.play().catch(function () {}); }
              }, true);
            })();
            {/raw}
          </script>

          <div class="flex flex-col sm:flex-row gap-4 mt-4 mb-6">
            <img
              src={@movie.thumbnail_url}
              alt={@movie.title}
              class="w-full sm:w-96 aspect-video object-cover rounded-box shadow"
            />
            <div>
              <h1 class="font-display text-2xl">{@movie.title}</h1>
              <p class="text-sm text-base-content/60 mb-2">{@face_count} unique face(s) recognised</p>
              <a href={@movie.player_path} class="btn btn-primary btn-sm">
                Watch
              </a>
              <div class="flex flex-col gap-3 mt-3 max-w-md">
                <div id="recognition-panel" class="p-3 rounded-box border border-primary/25">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="text-xs uppercase tracking-widest text-base-content/60">Face recognition</span>
                    <span id="recognition-status" class={@jobs.recognition.badge_class}>{@jobs.recognition.label}</span>
                  </div>
                  {%if @jobs.recognition.running?}
                    <div id="recognition-progress" class="mt-2">
                      <div class="flex justify-between text-xs text-base-content/70 mb-1">
                        <span>{@jobs.recognition.stage || "Starting…"}</span>
                        {%if @jobs.recognition.percent}<span>{@jobs.recognition.percent}%</span>{/if}
                      </div>
                      {%if @jobs.recognition.percent}
                        <progress class="progress progress-primary w-full transition-all" value={@jobs.recognition.percent} max="100"></progress>
                      {%else}
                        <progress class="progress progress-primary w-full"></progress>
                      {/if}
                      <p class="text-xs text-base-content/50 mt-1">
                        {%if @jobs.recognition.eta}{@jobs.recognition.eta} · {/if}This page refreshes itself when it's done.
                      </p>
                    </div>
                  {%else}
                    {%if @jobs.recognition.stalled?}
                      <p class="text-xs text-warning mt-2">
                        The last run stopped reporting (its process was probably stopped or killed). You can start it again.
                      </p>
                    {/if}
                    {%if @jobs.recognition.error}
                      <p class="text-xs text-error mt-2 break-words">Last run failed: {@jobs.recognition.error}</p>
                    {/if}
                    {%if @recognition_confirm}
                      <p class="text-xs text-warning mt-2">
                        This replaces all {@face_count} recognised faces, their names, and every focus vote for this video.
                      </p>
                      <div class="flex gap-2 mt-2">
                        <button id="recognition-confirm" type="button" $click="run_recognition" class="btn btn-xs btn-warning">
                          Yes, re-run
                        </button>
                        <button id="recognition-cancel" type="button" $click="cancel_recognition" class="btn btn-xs btn-ghost">
                          Cancel
                        </button>
                      </div>
                    {%else}
                      <button id="recognition-run" type="button" $click="recognition_clicked" class="btn btn-xs btn-secondary mt-2 gap-1 transition hover:-translate-y-0.5">
                        <span class="hero-sparkles w-4 h-4"></span>
                        {%if @movie.status == "done"}Re-run face recognition{%else}Run face recognition{/if}
                      </button>
                    {/if}
                  {/if}
                </div>

                <div id="versions-panel" class="p-3 rounded-box border border-primary/25">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="text-xs uppercase tracking-widest text-base-content/60">Quality &amp; downloads</span>
                    <span id="versions-status" class={@jobs.versions.badge_class}>{@jobs.versions.label}</span>
                  </div>
                  <ul id="versions-outputs" class="mt-2 flex flex-col gap-1">
                    {%for output <- @jobs.versions.outputs}
                      <li class="flex items-start gap-2 text-xs">
                        {%if output.ready?}
                          <span class="hero-check-circle w-4 h-4 text-success shrink-0"></span>
                        {%else}
                          <span class="hero-clock w-4 h-4 text-base-content/40 shrink-0"></span>
                        {/if}
                        <span>
                          <span class="font-medium">{output.label}</span>
                          <span class="text-base-content/60">{%if output.detail} · {output.detail}{%else} · not made yet{/if}</span>
                        </span>
                      </li>
                    {/for}
                  </ul>
                  {%if @jobs.versions.running?}
                    <div id="versions-progress" class="mt-2">
                      <div class="flex justify-between text-xs text-base-content/70 mb-1">
                        <span>{@jobs.versions.stage || "Starting…"}</span>
                        {%if @jobs.versions.percent}<span>{@jobs.versions.percent}%</span>{/if}
                      </div>
                      {%if @jobs.versions.percent}
                        <progress class="progress progress-secondary w-full transition-all" value={@jobs.versions.percent} max="100"></progress>
                      {%else}
                        <progress class="progress progress-secondary w-full"></progress>
                      {/if}
                      {%if @jobs.versions.eta}
                        <p class="text-xs text-base-content/50 mt-1">{@jobs.versions.eta}</p>
                      {/if}
                    </div>
                  {%else}
                    {%if @jobs.versions.stalled?}
                      <p class="text-xs text-warning mt-2">
                        The last run stopped reporting (its process was probably stopped or killed). You can start it again.
                      </p>
                    {/if}
                    {%if @jobs.versions.error}
                      <p class="text-xs text-error mt-2 break-words">Last run failed: {@jobs.versions.error}</p>
                    {/if}
                    <button id="versions-run" type="button" $click="run_versions" class="btn btn-xs btn-secondary mt-2 gap-1 transition hover:-translate-y-0.5">
                      <span class="hero-film w-4 h-4"></span>
                      {%if @jobs.versions.label == "Done"}Regenerate quality versions{%else}Generate quality versions{/if}
                    </button>
                  {/if}
                </div>

                {%if @job_message}
                  <p id="job-message" class="text-xs text-error">{@job_message}</p>
                {/if}
              </div>
              <details id="rename-movie-details" class="mt-2">
                <summary class="text-xs cursor-pointer text-base-content/60">Rename movie</summary>
                <div class="flex gap-1 mt-1">
                  <input
                    type="text"
                    value={@title_draft}
                    $change="update_title_draft"
                    placeholder="Movie name"
                    class="input input-xs input-bordered w-full max-w-xs"
                  />
                  <button type="button" $click="save_movie_title" class="btn btn-xs btn-primary">
                    Save
                  </button>
                </div>
              </details>
              <details id="listing-details-details" class="mt-2">
                <summary class="text-xs cursor-pointer text-base-content/60">
                  Edit listing details
                </summary>
                <div class="flex flex-col gap-1 mt-1 max-w-xs">
                  <textarea
                    value={@description_draft}
                    $change="update_description_draft"
                    placeholder="Blurb shown on the movie card"
                    class="textarea textarea-xs textarea-bordered w-full"
                  />
                  <input
                    type="date"
                    value={@event_date_draft}
                    $change="update_event_date_draft"
                    class="input input-xs input-bordered w-full"
                  />
                  <input
                    type="text"
                    value={@location_draft}
                    $change="update_location_draft"
                    placeholder="Location"
                    class="input input-xs input-bordered w-full"
                  />
                  <button type="button" $click="save_movie_details" class="btn btn-xs btn-primary">
                    Save
                  </button>
                </div>
              </details>
            </div>
          </div>

          {%if @faces == []}
            <div class="card card-stock shadow-xl">
              <div class="card-body">
                <p class="text-base-content/70">
                  {%if @movie.status == "processing"}
                    Curation is running now — check back in a bit.
                  {%else}
                    {%if @movie.status == "failed"}
                      Curation failed for this video. Use "Run face recognition" above to try again.
                    {%else}
                      {%if @movie.status == "done"}
                        No faces were found in this video.
                      {%else}
                        Not curated yet. Use "Run face recognition" above to scan it.
                      {/if}
                    {/if}
                  {/if}
                </p>
              </div>
            </div>
          {%else}
            <div class="flex flex-col lg:flex-row lg:items-start gap-6">
              <details id="scenes-section" open class="group/scenes lg:w-1/2 self-start w-full rounded-box border border-primary/25 card-stock">
                <summary class="sticky top-0 z-30 h-16 sm:h-14 px-4 rounded-box group-open/scenes:rounded-b-none group-open/scenes:border-b group-open/scenes:border-primary/20 group-open/scenes:shadow-sm list-none [&::-webkit-details-marker]:hidden cursor-pointer select-none flex items-center gap-3 bg-base-100 hover:bg-base-200 transition-colors">
                  <span class="hero-chevron-right w-5 h-5 shrink-0 text-primary transition-transform duration-200 group-open/scenes:rotate-90"></span>
                  <span class="flex-1 min-w-0 flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-0.5 sm:gap-3">
                    <h2 class="font-display text-lg sm:text-xl leading-tight">Scenes</h2>
                    <span class="text-xs text-base-content/60 sm:shrink-0">{@scene_count} scene(s)</span>
                  </span>
                </summary>
                <div class="p-3 flex flex-col gap-2">
                  <p class="text-sm text-base-content/60 mb-1">
                    A new scene starts whenever who's on screen changes.
                  </p>
                  {%for bucket <- @scene_buckets}
                    <details class="group/bucket rounded-box border border-primary/25 bg-base-100/40">
                      <summary class="sticky top-16 sm:top-14 z-20 px-3 py-2.5 rounded-box group-open/bucket:rounded-b-none group-open/bucket:shadow-sm list-none [&::-webkit-details-marker]:hidden cursor-pointer select-none flex items-center gap-3 bg-base-100 hover:bg-base-200 transition-colors">
                        <span class="hero-chevron-right w-4 h-4 shrink-0 text-primary transition-transform duration-200 group-open/bucket:rotate-90"></span>
                        <span class="flex-1 min-w-0 flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-0.5 sm:gap-3">
                          <span class="font-medium whitespace-nowrap">{bucket.label}</span>
                          <span class="text-xs text-base-content/60 whitespace-nowrap">{bucket.scene_count} scene(s)</span>
                        </span>
                      </summary>
                      <div class="p-3">
                        <div class="grid grid-cols-1 min-[480px]:grid-cols-2 sm:grid-cols-3 lg:grid-cols-2 gap-3">
                          {%for scene <- bucket.scenes}
                            <div
                              $click={:show_scene, start_ms: scene.start_ms, end_ms: scene.end_ms, movie_id: @movie.id}
                              class={
                                if scene.voted do
                                  "group relative overflow-hidden card bg-primary/10 border border-primary/40 shadow-sm min-h-40 cursor-pointer transition hover:shadow-md hover:border-primary"
                                else
                                  "group relative overflow-hidden card bg-base-200 shadow-sm min-h-40 cursor-pointer transition hover:shadow-md hover:bg-base-300"
                                end
                              }
                            >
                              <div class="absolute top-2 left-2 z-10 badge badge-neutral gap-1 text-xs sm:text-sm font-mono font-bold shadow whitespace-nowrap max-w-[calc(100%-1rem)]">
                                <span class="text-xs leading-none">▶</span> {scene.time}
                              </div>
                              <div class="absolute bottom-2 right-2 z-10 opacity-0 group-hover:opacity-100 transition pointer-events-none">
                                <div class="w-8 h-8 rounded-full bg-black/60 flex items-center justify-center text-white text-sm">
                                  ▶
                                </div>
                              </div>
                              <div class="card-body items-center justify-center text-center p-3 pt-9">
                                {%if scene.faces == []}
                                  <span class="text-xs text-base-content/60">no one recognised</span>
                                {%else}
                                  <div class="flex flex-wrap gap-2 justify-center">
                                    {%for face <- scene.faces}
                                      <div class="flex flex-col items-center gap-0.5">
                                        <div class="relative">
                                          <img
                                            src={"/admin/faces/#{face.id}/thumbnail"}
                                            title={face.label}
                                            class={
                                              if face.voted do
                                                "w-14 h-14 rounded-full object-cover ring-2 ring-primary"
                                              else
                                                "w-14 h-14 rounded-full object-cover ring ring-base-300"
                                              end
                                            }
                                          />
                                          {%if face.voted}
                                            <span class="absolute -top-1 -right-1 badge badge-primary badge-xs">✓</span>
                                          {/if}
                                        </div>
                                        <span class="text-xs text-base-content/60">👁 {face.votes}</span>
                                      </div>
                                    {/for}
                                  </div>
                                {/if}
                              </div>
                            </div>
                          {/for}
                        </div>
                      </div>
                    </details>
                  {/for}
                </div>
              </details>

              <details id="faces-section" open class="group/faces lg:w-1/2 self-start w-full rounded-box border border-primary/25 card-stock">
                <summary class="sticky top-0 z-30 h-16 sm:h-14 px-4 rounded-box group-open/faces:rounded-b-none group-open/faces:border-b group-open/faces:border-primary/20 group-open/faces:shadow-sm list-none [&::-webkit-details-marker]:hidden cursor-pointer select-none flex items-center gap-3 bg-base-100 hover:bg-base-200 transition-colors">
                  <span class="hero-chevron-right w-5 h-5 shrink-0 text-primary transition-transform duration-200 group-open/faces:rotate-90"></span>
                  <span class="flex-1 min-w-0 flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-0.5 sm:gap-3">
                    <h2 class="font-display text-lg sm:text-xl leading-tight">
                      <span class="sm:hidden">Faces</span><span class="hidden sm:inline">All recognised faces</span>
                    </h2>
                    <span class="text-xs text-base-content/60 sm:shrink-0">{@face_count}<span class="sm:hidden"> recognised</span></span>
                  </span>
                </summary>
                <div class="relative p-3">
                <div id="face-sort" class="flex flex-wrap items-center gap-1.5 mb-3">
                  <span class="text-xs text-base-content/60 mr-1">Sort by</span>
                  {%for option <- @face_sort_options}
                    <button
                      type="button"
                      id={"face-sort-#{option.key}"}
                      data-face-sort={option.key}
                      class="btn btn-xs btn-ghost border border-primary/20"
                    >
                      {option.label}
                    </button>
                  {/for}
                  <span class="text-xs text-base-content/50 ml-auto">{@named_face_count} of {@face_count} named</span>
                </div>
                <script>
                  {%raw}
                  // Face sort buttons: reorders the cards with CSS order, in the
                  // browser, rather than through a Hologram action (slow on this
                  // page). Reapplied whenever the cards data attributes change,
                  // e.g. after a vote or a new label. The choice is remembered
                  // per browser. No quote marks or backslashes in comments here:
                  // Hologram mangles both inside template scripts.
                  (function () {
                    if (window.__faceSortAttached) { return; }
                    window.__faceSortAttached = true;
                    var STORE = "admin-face-sort";
                    function saved() {
                      try { return localStorage.getItem(STORE) || "votes"; } catch (e) { return "votes"; }
                    }
                    function num(el, name) { return parseInt(el.getAttribute(name), 10) || 0; }
                    var keys = {
                      votes: function (c) { return num(c, "data-votes") * 1000000 + num(c, "data-scenes"); },
                      appearances: function (c) { return num(c, "data-scenes") * 1000000 + num(c, "data-votes"); },
                      named: function (c) { return num(c, "data-named") * 1000000 + num(c, "data-scenes"); },
                      unnamed: function (c) { return (1 - num(c, "data-named")) * 1000000 + num(c, "data-scenes"); }
                    };
                    function apply(sort) {
                      var grid = document.getElementById("face-grid");
                      if (!grid) { return; }
                      var key = keys[sort] || keys.votes;
                      Array.prototype.slice.call(grid.children)
                        .map(function (card, i) { return [key(card), i, card]; })
                        .sort(function (a, b) { return (b[0] - a[0]) || (a[1] - b[1]); })
                        .forEach(function (entry, position) { entry[2].style.order = position; });
                      var buttons = document.querySelectorAll("[data-face-sort]");
                      for (var i = 0; i < buttons.length; i++) {
                        var on = buttons[i].getAttribute("data-face-sort") === sort;
                        buttons[i].classList.toggle("btn-primary", on);
                        buttons[i].classList.toggle("btn-ghost", !on);
                        buttons[i].setAttribute("aria-pressed", on ? "true" : "false");
                      }
                    }
                    document.addEventListener("click", function (e) {
                      var button = e.target.closest && e.target.closest("[data-face-sort]");
                      if (!button) { return; }
                      var sort = button.getAttribute("data-face-sort");
                      try { localStorage.setItem(STORE, sort); } catch (err) {}
                      apply(sort);
                    });
                    var queued = false;
                    function schedule() {
                      if (queued) { return; }
                      queued = true;
                      requestAnimationFrame(function () { queued = false; apply(saved()); });
                    }
                    new MutationObserver(schedule).observe(document.documentElement, {
                      subtree: true, childList: true, attributes: true,
                      attributeFilter: ["data-votes", "data-named", "data-scenes"]
                    });
                    schedule();
                  })();
                  {/raw}
                </script>
                <div id="face-grid" class="grid grid-cols-1 min-[480px]:grid-cols-2 sm:grid-cols-3 lg:grid-cols-2 gap-4">
                  {%for face <- @faces}
                    <div
                      data-votes={face.focus_votes}
                      data-scenes={face.scene_count}
                      data-named={if(face.label && face.label != "", do: "1", else: "0")}
                      class={
                      if face.voted do
                        "card bg-primary/10 border border-primary/40 shadow-xl"
                      else
                        "card card-stock shadow-xl"
                      end
                    }>
                      <figure class="px-4 pt-4">
                        <img
                          src={"/admin/faces/#{face.id}/thumbnail"}
                          class={
                            if face.voted do
                              "rounded-box w-full aspect-square object-cover ring-2 ring-primary"
                            else
                              "rounded-box w-full aspect-square object-cover"
                            end
                          }
                        />
                      </figure>
                      <div class="card-body items-center text-center min-h-64">
                        <h2 class="card-title font-display text-base flex-wrap justify-center">
                          {face.label || "Face ##{face.id}"}
                          {%if face.voted}
                            <span class="badge badge-primary badge-xs align-middle">✓ voted</span>
                          {/if}
                        </h2>
                        {%if face.subtitle}
                          <p class="text-xs text-base-content/60 -mt-2">{face.subtitle}</p>
                        {/if}
                        <div class="flex flex-wrap justify-center gap-1.5">
                          <div class="badge badge-secondary badge-lg gap-1 text-sm sm:text-base whitespace-nowrap">
                            <span class="text-lg leading-none">👁</span> {face.focus_votes} in focus
                          </div>
                          <div class="badge badge-outline badge-lg gap-1 text-sm sm:text-base whitespace-nowrap" title="Number of scenes this face is on screen in">
                            <span class="text-base leading-none">🎬</span> in {face.scene_count} scene(s)
                          </div>
                        </div>
                        <div class="flex flex-wrap gap-x-2 gap-y-3 justify-center w-full max-h-24 overflow-y-auto pt-2 pr-2 [scrollbar-width:thin] [scrollbar-color:oklch(50%_0_0/50%)_transparent] [&::-webkit-scrollbar]:w-1.5 [&::-webkit-scrollbar-track]:bg-transparent [&::-webkit-scrollbar-thumb]:bg-[oklch(50%_0_0/50%)] [&::-webkit-scrollbar-thumb]:rounded-full">
                          {%for scene <- face.scenes}
                            <span
                              $click={:show_scene, start_ms: scene.start_ms, end_ms: scene.end_ms, movie_id: @movie.id}
                              title={
                                if scene.voted do
                                  "#{scene.votes} focus vote(s) — click to play"
                                else
                                  "Click to play"
                                end
                              }
                              class={
                                if scene.voted do
                                  "relative badge badge-primary cursor-pointer pr-4 whitespace-nowrap text-xs sm:text-sm"
                                else
                                  "relative badge badge-outline cursor-pointer hover:badge-primary pr-4 whitespace-nowrap text-xs sm:text-sm"
                                end
                              }
                            >
                              {scene.time}
                              <span class="absolute -top-2.5 -right-1.5 flex items-center gap-0.5 badge badge-neutral badge-sm px-1 shadow">
                                <span class="text-xs leading-none">▶</span>
                                {%if scene.voted}
                                  <span class="text-xs leading-none">{scene.votes}</span>
                                {/if}
                              </span>
                            </span>
                          {/for}
                        </div>
                        <details id={"label-details-#{face.id}"} class="w-full text-left">
                          <summary class="text-xs cursor-pointer text-base-content/60">Edit label</summary>
                          <div class="flex flex-col gap-1 mt-1">
                            <input
                              type="text"
                              value={Map.get(@label_drafts, face.id, %{label: ""}).label}
                              $change={:update_label_draft, face_id: face.id}
                              placeholder="Name"
                              class="input input-xs input-bordered w-full"
                            />
                            <input
                              type="text"
                              value={Map.get(@label_drafts, face.id, %{subtitle: ""}).subtitle}
                              $change={:update_subtitle_draft, face_id: face.id}
                              placeholder="Subtitle"
                              class="input input-xs input-bordered w-full"
                            />
                            <button
                              type="button"
                              $click={:save_label, face_id: face.id}
                              class="btn btn-xs btn-primary"
                            >
                              Save
                            </button>
                          </div>
                        </details>
                      </div>
                    </div>
                  {/for}
                </div>
                </div>
              </details>
            </div>
          {/if}

          {%if @scene_open}
          <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
            <div
              $click_outside="close_player"
              class="card-stock rounded-box shadow-2xl p-4 w-full max-w-5xl max-h-[90vh] overflow-y-auto"
            >
              <div class="flex justify-between items-center mb-2">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium">Scene preview (starts muted — unmute in the controls)</span>
                  {%if @current_preview_scene != nil}
                    <span class="badge badge-outline whitespace-nowrap">{@current_preview_scene.time}</span>
                  {/if}
                </div>
                <button $click="close_player" class="btn btn-xs btn-circle btn-ghost">✕</button>
              </div>

              <div class="flex flex-col lg:flex-row gap-4">
                <video
                  id="scene-video"
                  controls
                  muted
                  data-scene-boundaries={@scene_boundaries_json}
                  class="w-full lg:w-2/3 aspect-video rounded shrink-0"
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
                  {%if @current_preview_scene == nil}
                    <p class="text-sm text-base-content/60">No one recognised at this point in the scene.</p>
                  {%else}
                    {%if @current_preview_scene.faces == []}
                      <p class="text-sm text-base-content/60">No one recognised at this point in the scene.</p>
                    {%else}
                      <div class="flex flex-wrap gap-2">
                        {%for face <- @current_preview_scene.faces}
                          <button
                            $click={:focus_vote_clicked, movie_id: @movie.id, scene_start_ms: @current_preview_scene.start_ms, scene_end_ms: @current_preview_scene.end_ms, face_id: face.id, voter_id: @focus_session_id}
                            title={Enum.join(face.voted_ats, "\n")}
                            class={if face.mine? do "btn btn-primary h-auto py-2 px-3 gap-2" else "btn btn-outline h-auto py-2 px-3 gap-2" end}
                          >
                            <img src={"/admin/faces/#{face.id}/thumbnail"} class="w-10 h-10 rounded-full object-cover shrink-0" />
                            <span class="text-xs normal-case text-left leading-tight">
                              {face.label}<br />{face.votes} vote(s)
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
        {/if}
      </div>
    </div>
    """
  end
end
