defmodule ShubhVivahs.FocusPoll do
  @moduledoc """
  "Who's in focus?" live polling: for a given scene (a movie + time
  range), each viewer session can vote for any number of the faces
  present in that scene — voting for a face again removes that vote
  (toggle), independently of votes cast for the other faces in the
  same scene.
  """

  import Ecto.Query

  alias ShubhVivahs.FocusPoll.Vote
  alias ShubhVivahs.Repo

  @doc """
  Toggles this session's vote for one face within a scene: casts it if not
  already voted, retracts it if it was. Returns
  `{updated_counts, updated_voted_ats, voted?}`.
  """
  @spec toggle_vote(integer, integer, integer, integer, String.t()) ::
          {%{integer => non_neg_integer}, %{integer => [NaiveDateTime.t()]}, boolean}
  def toggle_vote(movie_id, scene_start_ms, scene_end_ms, face_id, session_id) do
    attrs = %{
      movie_id: movie_id,
      scene_start_ms: scene_start_ms,
      scene_end_ms: scene_end_ms,
      face_id: face_id,
      session_id: session_id
    }

    voted? =
      case Repo.get_by(Vote, attrs) do
        nil ->
          %Vote{} |> Vote.changeset(attrs) |> Repo.insert!()
          true

        existing ->
          Repo.delete!(existing)
          false
      end

    {scene_counts(movie_id, scene_start_ms, scene_end_ms),
     scene_voted_ats(movie_id, scene_start_ms, scene_end_ms), voted?}
  end

  @doc "Returns {face_id => vote count} for one scene."
  @spec scene_counts(integer, integer, integer) :: %{integer => non_neg_integer}
  def scene_counts(movie_id, scene_start_ms, scene_end_ms) do
    Vote
    |> where(movie_id: ^movie_id, scene_start_ms: ^scene_start_ms, scene_end_ms: ^scene_end_ms)
    |> group_by([v], v.face_id)
    |> select([v], {v.face_id, count(v.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Returns {face_id => every vote timestamp, most recent first} for one scene."
  @spec scene_voted_ats(integer, integer, integer) :: %{integer => [NaiveDateTime.t()]}
  def scene_voted_ats(movie_id, scene_start_ms, scene_end_ms) do
    Vote
    |> where(movie_id: ^movie_id, scene_start_ms: ^scene_start_ms, scene_end_ms: ^scene_end_ms)
    |> select([v], {v.face_id, v.inserted_at})
    |> Repo.all()
    |> Enum.group_by(fn {face_id, _inserted_at} -> face_id end, fn {_face_id, inserted_at} -> inserted_at end)
    |> Map.new(fn {face_id, timestamps} -> {face_id, Enum.sort(timestamps, {:desc, NaiveDateTime})} end)
  end

  @doc """
  Returns every vote for a movie as `%{scene_start_ms:, scene_end_ms:, face_id:, session_id:}`
  maps, for callers that need per-scene counts/my-vote across many scenes at
  once — one query instead of two per scene.
  """
  @spec all_votes(integer) :: [map]
  def all_votes(movie_id) do
    Vote
    |> where(movie_id: ^movie_id)
    |> select([v], %{
      scene_start_ms: v.scene_start_ms,
      scene_end_ms: v.scene_end_ms,
      face_id: v.face_id,
      session_id: v.session_id,
      inserted_at: v.inserted_at
    })
    |> Repo.all()
  end

  @doc "Returns {face_id => total vote count across all scenes} for a movie, for the admin view."
  @spec face_totals(integer) :: %{integer => non_neg_integer}
  def face_totals(movie_id) do
    Vote
    |> where(movie_id: ^movie_id)
    |> group_by([v], v.face_id)
    |> select([v], {v.face_id, count(v.id)})
    |> Repo.all()
    |> Map.new()
  end
end
