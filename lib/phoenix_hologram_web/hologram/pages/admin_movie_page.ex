defmodule PhoenixHologramWeb.Hologram.Pages.AdminMoviePage do
  @moduledoc """
  Per-movie scene browser: the movie's scene timeline (who's on screen,
  segmented every time that changes), plus every unique face recognised
  in it with a thumbnail and its own timestamp ranges.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias PhoenixHologram.FaceDetection
  alias PhoenixHologram.FaceDetection.{Movie, SceneIndex}
  alias PhoenixHologram.FocusPoll
  alias PhoenixHologram.Repo
  alias PhoenixHologramWeb.Hologram.Middleware.RequireSuperuser
  alias PhoenixHologramWeb.Hologram.Pages.AdminMoviesPage
  alias PhoenixHologramWeb.Hologram.Pages.PlayerPage

  route "/admin/movies/:id"

  middleware RequireSuperuser
  param :id, :integer

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  @bucket_ms 5 * 60 * 1000

  def init(params, component, server) do
    movie_record = Repo.get(Movie, params.id)
    preloaded = movie_record && Repo.preload(movie_record, faces: :detections)
    focus_session_id = Ecto.UUID.generate()

    votes_by_scene = if movie_record, do: scene_votes_by_key(movie_record.id), else: %{}

    scenes_list =
      if preloaded, do: movie_scenes(preloaded, votes_by_scene, focus_session_id), else: []

    scenes_by_key = Map.new(scenes_list, &{scene_key(&1), &1})

    faces =
      if preloaded,
        do:
          preloaded.faces
          |> Enum.map(&face_summary(&1, scenes_list))
          |> Enum.sort_by(& &1.focus_votes, :desc),
        else: []

    movie = movie_record && build_movie(movie_record)

    component =
      component
      |> put_state(:movie, movie)
      |> put_state(:focus_session_id, focus_session_id)
      |> put_state(:faces, faces)
      |> put_state(:face_count, length(faces))
      |> put_state(:scenes, scenes_by_key)
      |> put_state(:scene_buckets, scene_buckets(scenes_list))
      |> put_state(:scene_boundaries_json, scene_boundaries_json(scenes_list))
      |> put_state(:current_preview_scene, nil)
      |> put_state(:scene_open, false)

    server = if movie, do: put_subscription(server, {:focus_votes, movie.id}), else: server

    {component, server}
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

  # Actions run on the client (compiled to browser JS) — they can't do
  # database access, so this only extracts the form values and hands off
  # to a command (server-side) to actually persist them.
  def action(:save_label, params, component) do
    label = blank_to_nil(params.event["label"])
    subtitle = blank_to_nil(params.event["subtitle"])

    put_command(component, :persist_label,
      face_id: params.face_id,
      label: label,
      subtitle: subtitle
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

    put_state(component, :faces, faces)
  end

  def action(:save_movie_title, params, component) do
    title = blank_to_nil(params.event["title"])
    put_command(component, :persist_movie_title, movie_id: params.movie_id, title: title)
  end

  def action(:movie_title_saved, params, component) do
    JS.exec("""
    const details = document.getElementById('rename-movie-details');
    if (details) { details.open = false; }
    """)

    put_state(component, :movie, %{component.state.movie | title: params.title})
  end

  def action(:save_movie_details, params, component) do
    put_command(component, :persist_movie_details,
      movie_id: params.movie_id,
      description: blank_to_nil(params.event["description"]),
      event_date: blank_to_nil(params.event["event_date"]),
      location: blank_to_nil(params.event["location"])
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

    put_state(component, :movie, movie)
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
      update_face_focus(
        component.state.faces,
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

  # Mirrors votes_for_face_at/3: only the range whose *determining* scene
  # (the one find_scene_at/2 would resolve to at the range's start — same
  # scene that opens when the range is clicked) is the scene that just
  # changed gets the delta. focus_votes is re-summed from the (possibly
  # unchanged) ranges rather than adjusted by the raw delta, since a vote
  # can land on a scene that isn't any range's determining scene — the
  # header must stay the sum of what's actually shown below it (see
  # face_summary/2), not drift by a delta no pill reflected.
  #
  # This runs client-side on every vote, so unlike votes_for_face_at/3 it
  # can't afford to call find_scene_at/2 (an O(total_scenes) scan) once per
  # range: a face with dozens of ranges in a movie with hundreds of scenes
  # made every click freeze the tab. Since scene start_ms values are unique
  # and find_scene_at/2 always resolves to the last scene starting at or
  # before a point, "range's determining scene is the changed scene" is
  # equivalent to "range.start_ms falls in [changed_scene.start_ms, start_ms
  # of the next scene after it)" — a boundary computed once per vote below,
  # then checked per range in O(1).
  defp update_face_focus(faces, scenes, changed_scene, face_id, delta) do
    next_start = next_scene_start(scenes, changed_scene.start_ms)

    faces
    |> Enum.map(fn face ->
      if face.id == face_id do
        ranges =
          Enum.map(face.scenes, fn range ->
            if changed_scene.start_ms <= range.start_ms and
                 (is_nil(next_start) or range.start_ms < next_start) do
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
    |> Enum.sort_by(& &1.focus_votes, :desc)
  end

  # Written as a plain reduce (rather than Enum.min/2 with an empty-list
  # fallback) because Hologram's client-side Enum.min/2 doesn't support that
  # fallback arg the way Elixir does — it crashes with
  # "no function clause matching in :lists.min/1" instead of running it.
  defp next_scene_start(scenes, changed_start) do
    scenes
    |> scene_values()
    |> Enum.reduce(nil, fn scene, closest ->
      cond do
        scene.start_ms <= changed_start -> closest
        is_nil(closest) or scene.start_ms < closest -> scene.start_ms
        true -> closest
      end
    end)
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
  # given point in time, so a badge's vote count (see votes_for_face_at/3)
  # always agrees with the scene that opens when that badge is clicked.
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
      title: movie.title || movie.path,
      status: movie.status,
      description: movie.description,
      event_date_input: date_to_input(movie.event_date),
      location: movie.location,
      thumbnail_url: "/premiere/videos/#{movie.id}/thumbnail"
    }
  end

  defp date_to_input(nil), do: ""
  defp date_to_input(%Date{} = date), do: Date.to_iso8601(date)

  defp face_summary(face, scenes_list) do
    scenes =
      face.detections
      |> SceneIndex.ranges()
      |> Enum.map(fn range ->
        votes = votes_for_face_at(scenes_list, face.id, range.start_ms)

        %{
          time: format_scene(range),
          start_ms: range.start_ms,
          end_ms: range.end_ms,
          votes: votes,
          voted: votes > 0
        }
      end)

    # Derived as the sum of the pills above (rather than FocusPoll's raw
    # per-face total) so this header always agrees with what's visibly
    # enumerated underneath it — see votes_for_face_at/3 for why a pill's
    # count can be less than the number of votes actually cast for scenes
    # it spans.
    focus_votes = scenes |> Enum.map(& &1.votes) |> Enum.sum()

    %{
      id: face.id,
      label: face.label,
      subtitle: face.subtitle,
      scenes: scenes,
      focus_votes: focus_votes,
      voted: focus_votes > 0
    }
  end

  # The scenes voted on (see FocusPoll) are segmented by who's on screen
  # *together*, while a face's own timestamp ranges (SceneIndex.ranges/1)
  # are segmented by that face's own continuous appearances — the two
  # rarely share exact boundaries, so a range can span more than one
  # "who's on screen together" scene. Clicking a range always opens the
  # vote panel for whichever of those scenes is playing at the range's
  # *start* (see find_scene_at/2 and action(:show_scene)), so the badge
  # shows that one scene's vote count to always agree with the panel —
  # deliberately chosen over summing every scene the range overlaps, which
  # matches the "N in focus" total but can show more on the badge than a
  # click-through ever reveals.
  defp votes_for_face_at(scenes_list, face_id, start_ms) do
    case find_scene_at(scenes_list, start_ms) do
      nil -> 0
      scene -> scene.faces |> Enum.find(&(&1.id == face_id)) |> face_votes()
    end
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
              <Link to={PlayerPage, id: @movie.id} class="btn btn-primary btn-sm">
                Watch in Premiere Hall
              </Link>
              <details id="rename-movie-details" class="mt-2">
                <summary class="text-xs cursor-pointer text-base-content/60">Rename movie</summary>
                <form
                  method="post"
                  $submit={:save_movie_title, movie_id: @movie.id}
                  class="flex gap-1 mt-1"
                >
                  <input
                    type="text"
                    name="title"
                    value={@movie.title || ""}
                    placeholder="Movie name"
                    class="input input-xs input-bordered w-full max-w-xs"
                  />
                  <button type="submit" class="btn btn-xs btn-primary">Save</button>
                </form>
              </details>
              <details id="listing-details-details" class="mt-2">
                <summary class="text-xs cursor-pointer text-base-content/60">
                  Edit listing details
                </summary>
                <form
                  method="post"
                  $submit={:save_movie_details, movie_id: @movie.id}
                  class="flex flex-col gap-1 mt-1 max-w-xs"
                >
                  <textarea
                    name="description"
                    placeholder="Blurb shown on the movie card"
                    class="textarea textarea-xs textarea-bordered w-full"
                  >{@movie.description || ""}</textarea>
                  <input
                    type="date"
                    name="event_date"
                    value={@movie.event_date_input}
                    class="input input-xs input-bordered w-full"
                  />
                  <input
                    type="text"
                    name="location"
                    value={@movie.location || ""}
                    placeholder="Location"
                    class="input input-xs input-bordered w-full"
                  />
                  <button type="submit" class="btn btn-xs btn-primary">Save</button>
                </form>
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
                      Curation failed for this video. Try re-uploading it, or run `mix face_detection.ingest` again.
                    {%else}
                      {%if @movie.status == "done"}
                        No faces were found in this video.
                      {%else}
                        Not curated yet. Run `mix face_detection.ingest` for this movie first.
                      {/if}
                    {/if}
                  {/if}
                </p>
              </div>
            </div>
          {%else}
            <div class="flex flex-col lg:flex-row gap-8">
              <div class="lg:w-1/2">
                <h2 class="font-display text-xl mb-3">Scenes</h2>
                <p class="text-sm text-base-content/60 mb-3">
                  A new scene starts whenever who's on screen changes.
                </p>
                <div class="flex flex-col gap-2">
                  {%for bucket <- @scene_buckets}
                    <details class="collapse collapse-arrow card-stock border border-primary/25 rounded-box">
                      <summary class="collapse-title font-medium">
                        {bucket.label} — {bucket.scene_count} scene(s)
                      </summary>
                      <div class="collapse-content max-h-96 overflow-y-auto">
                        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-2 gap-3">
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
                              <div class="absolute top-2 left-2 z-10 badge badge-neutral gap-1 text-sm font-mono font-bold shadow">
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
              </div>

              <div class="lg:w-1/2">
                <h2 class="font-display text-xl mb-3">All recognised faces</h2>
                <div class="relative">
                <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-2 gap-4 max-h-[36rem] overflow-y-auto pr-4 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                  {%for face <- @faces}
                    <div class={
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
                        <div class="badge badge-secondary badge-lg gap-1 text-base">
                          <span class="text-lg leading-none">👁</span> {face.focus_votes} in focus
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
                                  "relative badge badge-primary cursor-pointer pr-4"
                                else
                                  "relative badge badge-outline cursor-pointer hover:badge-primary pr-4"
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
                          <form
                            method="post"
                            $submit={:save_label, face_id: face.id}
                            class="flex flex-col gap-1 mt-1"
                          >
                            <input
                              type="text"
                              name="label"
                              value={face.label || ""}
                              placeholder="Name"
                              class="input input-xs input-bordered w-full"
                            />
                            <input
                              type="text"
                              name="subtitle"
                              value={face.subtitle || ""}
                              placeholder="Subtitle"
                              class="input input-xs input-bordered w-full"
                            />
                            <button type="submit" class="btn btn-xs btn-primary">Save</button>
                          </form>
                        </details>
                      </div>
                    </div>
                  {/for}
                </div>
                <div class="pointer-events-none absolute inset-y-0 right-0 w-1.5 rounded-full bg-base-300/50">
                  <div class="w-1.5 h-1/5 rounded-full bg-[oklch(50%_0_0/70%)]"></div>
                </div>
                </div>
              </div>
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
