defmodule ShubhVivahsWeb.LegacyAdminRedirectController do
  @moduledoc """
  Redirects for admin URLs that changed shape when admin movie pages moved
  to `/admin/<uploader>/<slug>` (see `ShubhVivahs.MovieSlug`):
  `/admin/movies/<id>` and `/admin/analytics/export.csv`.

  These live in the Phoenix router rather than Hologram middleware because
  Hologram's route matcher commits to a literal segment ("movies" from
  LegacyAdminMoviePage's route, "analytics" from AdminAnalyticsPage's) and
  doesn't fall back to `/admin/:uploader/:name`, so these paths never reach
  a Hologram page — they fall through to this router.
  """

  use ShubhVivahsWeb, :controller

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.MovieSlug
  alias ShubhVivahs.Repo

  def admin_movie(conn, %{"id" => id}) do
    target =
      with {int, ""} <- Integer.parse(id),
           %Movie{} = movie <- Repo.get(Movie, int) do
        MovieSlug.admin_path(movie)
      else
        _ -> "/admin"
      end

    redirect(conn, to: target)
  end

  def analytics_csv(conn, _params) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    redirect(conn, to: "/admin/analytics.csv" <> query)
  end
end
