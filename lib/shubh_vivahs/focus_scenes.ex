defmodule ShubhVivahs.FocusScenes do
  @moduledoc """
  A movie's "Who's in focus?" scenes — when each starts and ends, and the
  faces on screen with their focus votes — as plain maps, for the player.

  PlayerPage only keeps the current scene in its state; the browser
  fetches the whole list once as JSON (`VideoController.scenes/2`) and
  hands each scene to the page as playback reaches it. Hologram's client
  runtime walks a whole value on every pattern match, so holding ~2,000
  scenes (a TV episode) in page state made every scene change take
  ~300ms+, and putting them in state as one big JSON string made the
  server-side render hang.
  """

  alias ShubhVivahs.FaceDetection.SceneIndex
  alias ShubhVivahs.FocusPoll
  alias ShubhVivahs.Repo

  @doc """
  Every scene of `movie`, in order. `session_id` marks which faces that
  viewer has voted for (`mine?`); nil marks none.
  """
  def scenes(movie, session_id) do
    votes_by_scene =
      movie.id
      |> FocusPoll.all_votes()
      |> Enum.group_by(&{&1.scene_start_ms, &1.scene_end_ms})

    preloaded_faces = movie |> Repo.preload(faces: :detections) |> Map.fetch!(:faces)
    face_labels = Map.new(preloaded_faces, fn face -> {face.id, face.label} end)

    preloaded_faces
    |> Enum.flat_map(& &1.detections)
    |> SceneIndex.scenes()
    |> Enum.map(fn scene ->
      scene_votes = Map.get(votes_by_scene, {scene.start_ms, scene.end_ms}, [])

      %{
        start_ms: scene.start_ms,
        end_ms: scene.end_ms,
        time: format_scene(scene),
        faces: faces(scene.face_ids, face_labels, scene_votes, session_id)
      }
    end)
  end

  @doc """
  The faces of one scene with their votes, given labels (`%{id => label}`)
  and that scene's votes (`FocusPoll.scene_votes/3` shape).
  """
  def faces(face_ids, face_labels, scene_votes, session_id) do
    votes_by_face = Enum.group_by(scene_votes, & &1.face_id)

    my_voted_faces =
      scene_votes |> Enum.filter(&(&1.session_id == session_id)) |> MapSet.new(& &1.face_id)

    face_ids
    |> Enum.map(fn face_id ->
      face_votes = Map.get(votes_by_face, face_id, [])

      %{
        id: face_id,
        label: Map.get(face_labels, face_id) || "Face ##{face_id}",
        thumbnail_url: "/premiere/faces/#{face_id}/thumbnail.jpg",
        votes: length(face_votes),
        mine?: MapSet.member?(my_voted_faces, face_id),
        voted_ats: face_votes |> voted_ats() |> Enum.map(&format_timestamp/1)
      }
    end)
    |> mark_leading()
  end

  @doc "Flags every face tied for the most votes (`leading?`); an all-zero scene marks no one."
  def mark_leading(faces) do
    max_votes = faces |> Enum.map(& &1.votes) |> Enum.reduce(0, &max/2)

    Enum.map(faces, &Map.put(&1, :leading?, max_votes > 0 and &1.votes == max_votes))
  end

  @doc "Vote timestamp as shown in the panel's tooltip."
  def format_timestamp(nil), do: nil
  def format_timestamp(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S UTC")

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
end
