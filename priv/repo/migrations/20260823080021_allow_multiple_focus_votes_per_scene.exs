defmodule ShubhVivahs.Repo.Migrations.AllowMultipleFocusVotesPerScene do
  use Ecto.Migration

  def change do
    drop unique_index(:focus_votes, [:movie_id, :scene_start_ms, :scene_end_ms, :session_id],
           name: :focus_votes_movie_scene_session_index
         )

    create unique_index(
             :focus_votes,
             [:movie_id, :scene_start_ms, :scene_end_ms, :face_id, :session_id],
             name: :focus_votes_movie_scene_face_session_index
           )
  end
end
