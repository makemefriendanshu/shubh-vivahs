defmodule ShubhVivahs.Engagement do
  @moduledoc """
  Likes, views, and comments for movies, and likes on those comments. A movie
  like can be toggled on and off within a single page view (the page tracks
  the id of the like it just added so it can remove that exact row again),
  but that "liked" state isn't remembered across reloads - each fresh page
  load starts unliked, regardless of past likes from that session. Comment
  likes are keyed by (comment, session_id) instead, so clicking again within
  the same session toggles it off rather than adding another one. Movie views
  are recorded once per play (see PlayerPage's client-side play detection)
  and simply accumulate - there's no undo, unlike likes.
  """

  import Ecto.Query

  alias ShubhVivahs.Engagement.{Comment, CommentLike, MovieLike, MovieView}
  alias ShubhVivahs.Repo

  @spec movie_likes_count(integer) :: non_neg_integer
  def movie_likes_count(movie_id) do
    MovieLike |> where(movie_id: ^movie_id) |> Repo.aggregate(:count)
  end

  @spec movie_views_count(integer) :: non_neg_integer
  def movie_views_count(movie_id) do
    MovieView |> where(movie_id: ^movie_id) |> Repo.aggregate(:count)
  end

  @doc "Records a view of a movie for this session. Returns the new total view count."
  @spec record_movie_view(integer, String.t()) :: non_neg_integer
  def record_movie_view(movie_id, session_id) do
    %MovieView{}
    |> MovieView.changeset(%{movie_id: movie_id, session_id: session_id})
    |> Repo.insert!()

    movie_views_count(movie_id)
  end

  @doc "Adds a like to a movie. Returns {like_id, new_count} - keep like_id to unlike it again."
  @spec add_movie_like(integer, String.t()) :: {integer, non_neg_integer}
  def add_movie_like(movie_id, session_id) do
    like =
      %MovieLike{}
      |> MovieLike.changeset(%{movie_id: movie_id, session_id: session_id})
      |> Repo.insert!()

    {like.id, movie_likes_count(movie_id)}
  end

  @doc """
  Removes a specific like (by the id returned from add_movie_like/2), scoped
  to the given movie and session so a tampered id can't delete someone
  else's like. Returns the new total like count.
  """
  @spec remove_movie_like(integer, integer, String.t()) :: non_neg_integer
  def remove_movie_like(like_id, movie_id, session_id) do
    MovieLike
    |> where(id: ^like_id, movie_id: ^movie_id, session_id: ^session_id)
    |> Repo.delete_all()

    movie_likes_count(movie_id)
  end

  @doc """
  Lists this movie's top-level comments (newest first), each with its
  replies nested under `:replies` (oldest first, one level deep).
  """
  @spec list_comments(integer, String.t()) :: [map]
  def list_comments(movie_id, session_id) do
    all =
      Comment
      |> where(movie_id: ^movie_id)
      |> order_by(asc: :inserted_at)
      |> Repo.all()

    by_parent = Enum.group_by(all, & &1.parent_id)

    by_parent
    |> Map.get(nil, [])
    |> Enum.reverse()
    |> Enum.map(fn comment ->
      replies = by_parent |> Map.get(comment.id, []) |> Enum.map(&comment_view(&1, session_id))
      comment |> comment_view(session_id) |> Map.put(:replies, replies)
    end)
  end

  @doc "Adds a top-level comment, or a reply when `parent_id` is given."
  @spec add_comment(integer, String.t(), String.t(), String.t(), integer | nil) ::
          {:ok, Comment.t()} | {:error, Ecto.Changeset.t()}
  def add_comment(movie_id, body, session_id, author_name, parent_id \\ nil) do
    %Comment{}
    |> Comment.changeset(%{
      movie_id: movie_id,
      body: body,
      session_id: session_id,
      author_name: author_name,
      parent_id: parent_id
    })
    |> Repo.insert()
  end

  @doc """
  Deletes a comment (and its replies, if any) if it belongs to `session_id`.
  No-op (returns `{:error, :not_found_or_forbidden}`) otherwise.
  """
  @spec delete_comment(integer, String.t()) :: {:ok, Comment.t()} | {:error, atom}
  def delete_comment(comment_id, session_id) do
    case Repo.get(Comment, comment_id) do
      %Comment{session_id: ^session_id} = comment ->
        Repo.delete_all(from c in Comment, where: c.parent_id == ^comment.id)
        Repo.delete(comment)

      _ ->
        {:error, :not_found_or_forbidden}
    end
  end

  @spec comment_likes_count(integer) :: non_neg_integer
  def comment_likes_count(comment_id) do
    CommentLike |> where(comment_id: ^comment_id) |> Repo.aggregate(:count)
  end

  @spec comment_liked?(integer, String.t()) :: boolean
  def comment_liked?(comment_id, session_id) do
    Repo.exists?(
      from c in CommentLike, where: c.comment_id == ^comment_id and c.session_id == ^session_id
    )
  end

  @doc "Toggles this session's like on a comment. Returns {:liked | :unliked, new_count}."
  @spec toggle_comment_like(integer, String.t()) :: {:liked | :unliked, non_neg_integer}
  def toggle_comment_like(comment_id, session_id) do
    # mode: :immediate grabs the SQLite write lock at BEGIN instead of the default
    # deferred mode (which only grabs it at the first write). Without it, two
    # toggles racing on the same (comment_id, session_id) both take their read
    # snapshot before either writes, so the second one's write can't be
    # reconciled with its now-stale snapshot and fails with an unretriable
    # "database is busy" (SQLITE_BUSY_SNAPSHOT) regardless of busy_timeout.
    Repo.transaction(
      fn ->
        case Repo.get_by(CommentLike, comment_id: comment_id, session_id: session_id) do
          nil ->
            %CommentLike{}
            |> CommentLike.changeset(%{comment_id: comment_id, session_id: session_id})
            |> Repo.insert!()

            {:liked, comment_likes_count(comment_id)}

          like ->
            Repo.delete!(like)
            {:unliked, comment_likes_count(comment_id)}
        end
      end,
      mode: :immediate
    )
    |> then(fn {:ok, result} -> result end)
  end

  defp comment_view(comment, session_id) do
    name = display_name(comment.author_name)

    %{
      id: comment.id,
      body: comment.body,
      author_name: name,
      author_initial: name |> String.slice(0, 1) |> String.upcase(),
      likes_count: comment_likes_count(comment.id),
      liked?: comment_liked?(comment.id, session_id),
      own?: comment.session_id == session_id
    }
  end

  defp display_name(nil), do: "Anonymous"
  defp display_name(""), do: "Anonymous"
  defp display_name(name), do: name
end
