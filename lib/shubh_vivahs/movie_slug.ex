defmodule ShubhVivahs.MovieSlug do
  @moduledoc """
  Readable movie URLs — the player, `/gallery/<uploader>/<slug>` for wedding
  films or `/library/<uploader>/<slug>` for media library titles, and the
  admin scene browser, `/admin/<uploader>/<slug>` — e.g.
  `/premiere/anshuman/reception` or
  `/premiere/shubhvivahs/game-of-thrones-s01e01-winter-is-coming`.

  * `<slug>` comes from the movie's title, is stored on the movie
    (`movies.slug`, unique across the site), and is regenerated when the
    movie is renamed. Movies created before slugs existed get one the
    first time a link to them is built (`ensure/1`).
  * `<uploader>` comes from the uploader's name — "shubhvivahs" for
    movies with no uploader (seed films and media library imports). It's
    only for readability: the slug alone identifies the movie, and a URL
    with the wrong uploader redirects to the right one.

  Old `/premiere/…` links keep working (they redirect here). Names that
  are other routes' second segment — "videos", "faces" (`/premiere/…` file
  endpoints), "media" (`/library/media/…`), "movies", "analytics",
  "promo-requests" (`/admin/…`) — are never used as an uploader segment.
  """

  import Ecto.Query

  alias ShubhVivahs.Accounts.User
  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.Repo

  @no_uploader "shubhvivahs"
  @reserved_uploaders ~w(videos faces media movies analytics promo-requests)
  @max_length 80

  @doc """
  The player path for `movie`, assigning it a slug first if it has none:
  `/gallery/<uploader>/<slug>` for wedding films, `/library/<uploader>/<slug>`
  for media library titles.
  """
  @spec path(Movie.t()) :: String.t()
  def path(%Movie{} = movie) do
    %{uploader_slug: uploader, slug: slug} = link_fields(movie)
    "/#{section(movie)}/#{uploader}/#{slug}"
  end

  @doc "Which part of the site a movie lives in: `\"library\"` or `\"gallery\"`."
  @spec section(Movie.t()) :: String.t()
  def section(%Movie{id: id}) do
    library? = Repo.exists?(from i in ShubhVivahs.Library.MediaItem, where: i.movie_id == ^id)
    if library?, do: "library", else: "gallery"
  end

  @doc "The admin scene-browser path for `movie`: `/admin/<uploader>/<slug>`."
  @spec admin_path(Movie.t()) :: String.t()
  def admin_path(%Movie{} = movie) do
    %{uploader_slug: uploader, slug: slug} = link_fields(movie)
    "/admin/#{uploader}/#{slug}"
  end

  @doc """
  `%{uploader_slug:, slug:}` for building a `<Link to={PlayerPage, uploader: …, name: …}>`
  in a page's state, assigning a slug first if needed.
  """
  @spec link_fields(Movie.t()) :: %{uploader_slug: String.t(), slug: String.t()}
  def link_fields(%Movie{} = movie) do
    movie = ensure(movie)
    %{uploader_slug: uploader_slug(movie), slug: movie.slug}
  end

  @doc "Returns `movie` with a slug, generating and saving one if it has none."
  @spec ensure(Movie.t()) :: Movie.t()
  def ensure(%Movie{slug: slug} = movie) when is_binary(slug), do: movie

  def ensure(%Movie{} = movie) do
    slug = unique(movie.title || "video", movie.id)
    {1, _} = Repo.update_all(from(m in Movie, where: m.id == ^movie.id), set: [slug: slug])
    %{movie | slug: slug}
  end

  @doc "A fresh slug for `title`, unique among movies other than `movie_id`."
  @spec unique(String.t(), integer | nil) :: String.t()
  def unique(title, movie_id) do
    base = slugify(title)

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(fn candidate ->
      not Repo.exists?(from m in Movie, where: m.slug == ^candidate and m.id != ^(movie_id || 0))
    end)
  end

  @doc "The uploader segment for `movie` (see moduledoc)."
  @spec uploader_slug(Movie.t()) :: String.t()
  def uploader_slug(%Movie{user_id: user_id}), do: uploader_slug_for(user_id)

  @doc "The uploader segment for a user id (also used for photo albums)."
  @spec uploader_slug_for(integer | nil) :: String.t()
  def uploader_slug_for(nil), do: @no_uploader

  def uploader_slug_for(user_id) do
    case Repo.one(from u in User, where: u.id == ^user_id, select: u.name) do
      nil -> @no_uploader
      name -> name |> slugify() |> avoid_reserved()
    end
  end

  @doc "The uploader's name as people see it (for breadcrumbs), or nil."
  @spec uploader_name_for(integer | nil) :: String.t() | nil
  def uploader_name_for(nil), do: nil

  def uploader_name_for(user_id),
    do: Repo.one(from u in User, where: u.id == ^user_id, select: u.name)

  @doc "Finds a movie by slug, or nil."
  @spec get(String.t()) :: Movie.t() | nil
  def get(slug) when is_binary(slug), do: Repo.get_by(Movie, slug: slug)

  @doc "Lower-case ASCII words joined by \"-\", e.g. \"Mother's Mercy!\" -> \"mothers-mercy\"."
  @spec slugify(String.t()) :: String.t()
  def slugify(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\x00-\x7F]/u, "")
    |> String.downcase()
    |> String.replace(~r/['’]/u, "")
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, @max_length)
    |> String.trim_trailing("-")
    |> case do
      "" -> "video"
      slug -> slug
    end
  end

  defp avoid_reserved(slug) when slug in @reserved_uploaders, do: slug <> "-user"
  defp avoid_reserved(slug), do: slug
end
