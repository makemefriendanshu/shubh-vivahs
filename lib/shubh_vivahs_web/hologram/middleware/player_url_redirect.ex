defmodule ShubhVivahsWeb.Hologram.Middleware.PlayerUrlRedirect do
  @moduledoc """
  Redirects for the readable movie URLs (see `ShubhVivahs.MovieSlug`),
  run as middleware because in Hologram 0.10 only middleware can end a
  page request early — a `put_redirect/2` in `init/3` still renders the
  page. Two jobs, picked with the `:mode` option:

    * `:player` (PlayerPage, `/premiere/:uploader/:name`):
      - `/premiere/videos/<id>` — the old stream URL, which this route now
        catches because Hologram's router runs before Phoenix's — goes to
        `/premiere/videos/<id>/stream`;
      - a known movie under the wrong uploader goes to its canonical URL.
    * `:legacy` (LegacyPlayerPage, `/premiere/:id`): old id links go to the
      readable URL, or to Premiere Hall for a private movie when signed
      out (so an old link can't reveal its title).
    * `:admin` (AdminMoviePage, `/admin/:uploader/:name`): a known movie
      under the wrong uploader goes to its canonical URL; the old
      `/admin/movies/<id>` and `/admin/analytics/export.csv` URLs, which
      this route also catches, go to their new homes.
    * `:admin_legacy` (LegacyAdminMoviePage, `/admin/movies/:uploader/:name`):
      the earlier, longer readable admin URL goes to the short one.

  Params come from the request path on a full page load, or from the query
  string on Hologram's client-side page requests.
  """

  use Hologram.Middleware

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.MovieSlug
  alias ShubhVivahs.Repo

  @impl Hologram.Middleware
  def call(server, opts) do
    case Keyword.fetch!(opts, :mode) do
      :player -> player(server, Keyword.fetch!(opts, :section))
      :premiere_legacy -> premiere_legacy(server)
      :gallery_index -> put_redirect(server, "/gallery" <> query_suffix(server))
      :legacy -> legacy(server)
      :admin -> admin(server)
      :admin_legacy -> admin_legacy(server)
    end
  end

  # /gallery/:uploader/:name and /library/:uploader/:name.
  defp player(server, section) do
    case route_params(server, "/#{section}") do
      # Same shape as this route, so it lands here: the media library file
      # URL before it moved to /library/media/<id>/file.
      {"media", id} when section == :library ->
        put_redirect(server, "/library/media/#{id}/file" <> query_suffix(server))

      {uploader, name} ->
        movie = MovieSlug.get(name)

        # Right movie, wrong section (a library title under /gallery) or
        # wrong uploader: go to its canonical URL.
        if visible?(movie, server) and MovieSlug.path(movie) != "/#{section}/#{uploader}/#{name}" do
          put_redirect(server, MovieSlug.path(movie) <> query_suffix(server))
        else
          server
        end

      nil ->
        server
    end
  end

  # /premiere/:uploader/:name — the player before it split into /gallery and
  # /library — plus the old 3-segment stream URL /premiere/videos/<id>.
  defp premiere_legacy(server) do
    case route_params(server, "/premiere") do
      {"videos", id} ->
        put_redirect(server, "/premiere/videos/#{id}/stream" <> query_suffix(server))

      {_uploader, name} ->
        movie = MovieSlug.get(name)

        put_redirect(
          server,
          if(visible?(movie, server), do: MovieSlug.path(movie), else: "/gallery")
        )

      nil ->
        put_redirect(server, "/gallery")
    end
  end

  defp legacy(server) do
    movie = legacy_movie(server, "/premiere")
    target = if visible?(movie, server), do: MovieSlug.path(movie), else: "/gallery"
    put_redirect(server, target)
  end

  # Admin pages sit behind RequireSuperuser (listed first on the page), so
  # every movie is visible here.
  defp admin(server) do
    case route_params(server, "/admin") do
      # Same shape as this route, so it lands here: the old id-based admin
      # URL (/admin/movies/<id>) and the old CSV export URL.
      {"movies", id} ->
        case movie_by_id(id) do
          nil -> put_redirect(server, "/admin")
          movie -> put_redirect(server, MovieSlug.admin_path(movie))
        end

      {"analytics", "export.csv"} ->
        put_redirect(server, "/admin/analytics.csv" <> query_suffix(server))

      {uploader, name} ->
        movie = MovieSlug.get(name)

        if movie && MovieSlug.uploader_slug(movie) != uploader,
          do: put_redirect(server, MovieSlug.admin_path(movie) <> query_suffix(server)),
          else: server

      nil ->
        server
    end
  end

  # /admin/movies/<uploader>/<slug> — the readable admin URL before it was
  # shortened to /admin/<uploader>/<slug>.
  defp admin_legacy(server) do
    movie =
      case route_params(server, "/admin/movies") do
        {_uploader, name} -> MovieSlug.get(name)
        nil -> nil
      end

    put_redirect(server, if(movie, do: MovieSlug.admin_path(movie), else: "/admin"))
  end

  defp route_params(server, base) do
    case Regex.run(~r{^#{base}/([^/]+)/([^/]+)/?$}, server.path || "") do
      [_, uploader, name] -> {URI.decode(uploader), URI.decode(name)}
      nil -> with %{"uploader" => u, "name" => n} <- server.query, do: {u, n}, else: (_ -> nil)
    end
  end

  defp legacy_movie(server, base) do
    id =
      case Regex.run(~r{^#{base}/([^/]+)/?$}, server.path || "") do
        [_, id] -> id
        nil -> server.query["id"]
      end

    movie_by_id(id)
  end

  defp movie_by_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> Repo.get(Movie, int)
      _ -> nil
    end
  end

  defp movie_by_id(_id), do: nil

  # A private movie is "not found" for signed-out visitors (see PlayerPage).
  defp visible?(nil, _server), do: false
  defp visible?(%Movie{public: public}, server), do: public or not is_nil(server.user_id)

  defp query_suffix(%{raw_query: q}) when is_binary(q) and q != "", do: "?" <> q
  defp query_suffix(_server), do: ""
end
