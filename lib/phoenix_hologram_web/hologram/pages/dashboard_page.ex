defmodule PhoenixHologramWeb.Hologram.Pages.DashboardPage do
  @moduledoc """
  "My account" dashboard, gated behind `RequireAuthenticatedUser` — an
  anonymous visitor is redirected to LoginPage before this ever renders.
  The signed-in identity (name/email, Log Out) and Premium status are
  real, per-user data (`PhoenixHologram.Accounts`). The wedding-journey
  content (curation %, timeline status, uploaded videos) is the same
  real `Movie` catalog HomePage's "Analyze Our Core Example" section
  shows (`PhoenixHologram.FaceDetection.list_movies_ordered/0`) — this
  app has no per-couple event data model, just one shared catalog of
  ingested films, so a couple's "wedding journey" is that catalog's
  real curation state: `%` complete is `done` movies over the total,
  and the video list shows each movie's actual `status`
  (pending/processing/done/failed), not sample data — and it's live: this
  page subscribes to the `:movies_changed` broadcast channel
  (`put_subscription/2`) that `PhoenixHologram.VideoUpload` fires once a
  background ingestion finishes, so a Pending/Processing badge flips to
  Curated/Failed on its own, no manual reload needed. Superusers see
  Premium as already unlocked (`Accounts.premium?/1`) instead of the
  "Get Premium" upsell. A half-width "Account Settings" card is the first
  card in the curation grid (stacks full-width above the rest on mobile,
  matching how the other cards in that grid already respond) — every
  real field on the account (photo, name, email, phone, wedding date),
  plus a "Superuser" badge and access-tier line when
  `Accounts.superuser?/1` is true (nothing shown there for a regular
  account — no fake paid-tier names exist on the `User` schema, so this
  only ever states the one real tier distinction the app has: superuser
  vs. not) — with a link to the fully wired AccountSettingsPage for
  editing. Buttons that have a genuine
  destination in the app today
  (Edit Event Details, Pricing, Generate Shareable Link, Invite Team)
  link there for real; the rest ("View Timeline Preview") are
  decorative, matching how PricingPage handles features with no
  backend yet.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias PhoenixHologram.Accounts
  alias PhoenixHologram.FaceDetection
  alias PhoenixHologramWeb.Hologram.Middleware.RequireAuthenticatedUser
  alias PhoenixHologramWeb.Hologram.Pages.AccountSettingsPage
  alias PhoenixHologramWeb.Hologram.Pages.EditEventDetailsPage
  alias PhoenixHologramWeb.Hologram.Pages.GenerateLinkPage
  alias PhoenixHologramWeb.Hologram.Pages.InviteTeamPage
  alias PhoenixHologramWeb.Hologram.Pages.PlayerPage
  alias PhoenixHologramWeb.Hologram.Pages.UpgradePage
  alias PhoenixHologramWeb.Hologram.Pages.UploadPage

  route "/dashboard"

  middleware RequireAuthenticatedUser

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server) do
    # Extracted into plain strings/maps rather than putting the raw
    # `Accounts.User` Ecto struct into template state — that duplicated
    # the email on the client after hydration (worked fine in the initial
    # server-rendered HTML, so it's a client-side quirk specific to
    # rendering Ecto struct fields, not present with plain maps/strings
    # elsewhere in this app).
    user = get_stash(server, :current_user)
    server = put_subscription(server, :movies_changed)

    component =
      put_state(
        component,
        [
          current_user_name: user.name,
          current_user_email: user.email,
          current_user_phone: user.phone,
          current_user_avatar_url: user.avatar_url,
          current_user_wedding_date: format_date(user.wedding_date),
          superuser?: Accounts.superuser?(user),
          premium?: Accounts.premium?(user)
        ] ++ movie_stats()
      )

    {component, server}
  end

  # Dispatched via Hologram.Realtime.broadcast_action/2 from
  # PhoenixHologram.VideoUpload once a background ingestion finishes (see
  # its moduledoc) — every open Dashboard tab re-fetches the movie catalog
  # instead of showing a stale "Pending Review"/"Processing" badge until
  # the couple happens to reload the page.
  def action(:movie_ingested, _params, component) do
    put_command(component, :refresh_movie_stats)
  end

  def action(:movie_stats_refreshed, params, component) do
    put_state(component,
      completion_percentage: params.completion_percentage,
      done_count: params.done_count,
      total_count: params.total_count,
      next_movie_title: params.next_movie_title,
      movies: params.movies
    )
  end

  # Fallback safety net in case the broadcast above is ever missed (e.g.
  # the realtime connection dropped and reconnected in between) - fires
  # every 15s from the polling script near the template's end. Matches
  # AdminAnalyticsPage's :auto_refresh pattern.
  def action(:movies_poll, _params, component) do
    put_command(component, :refresh_movie_stats)
  end

  def action(:log_out_clicked, _params, component) do
    put_command(component, :log_out)
  end

  # A real browser navigation (not put_page/Link) to "/" — matching how the
  # rest of this app always reaches HomePage via a plain `<a href="/">`
  # (see DefaultLayout's logo and "Home" links) rather than client-side
  # SPA navigation, which doesn't reliably handle the root route.
  def action(:logged_out, _params, component) do
    JS.exec("window.location.href = '/';")
    component
  end

  def command(:refresh_movie_stats, _params, server) do
    put_action(server, :movie_stats_refreshed, movie_stats())
  end

  def command(:log_out, _params, server) do
    server
    |> delete_user_id()
    |> put_action(:logged_out)
  end

  defp movie_stats do
    movies = FaceDetection.list_movies_ordered()
    total_count = length(movies)
    done_count = Enum.count(movies, &(&1.status == "done"))
    completion_percentage = if total_count > 0, do: round(done_count / total_count * 100), else: 0
    next_movie = Enum.find(movies, &(&1.status != "done"))

    [
      completion_percentage: completion_percentage,
      done_count: done_count,
      total_count: total_count,
      next_movie_title: next_movie && movie_title(next_movie),
      movies: Enum.map(movies, &movie_view/1)
    ]
  end

  defp movie_view(movie) do
    %{
      id: movie.id,
      title: movie_title(movie),
      badge_label: status_label(movie.status),
      badge_class: status_class(movie.status)
    }
  end

  defp movie_title(movie), do: movie.title || movie.path

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d %b %Y")

  defp status_label("done"), do: "Curated"
  defp status_label("processing"), do: "Processing"
  defp status_label("failed"), do: "Failed"
  defp status_label(_pending), do: "Pending Review"

  defp status_class("done"), do: "badge badge-success badge-sm"
  defp status_class("processing"), do: "badge badge-info badge-sm"
  defp status_class("failed"), do: "badge badge-error badge-sm"
  defp status_class(_pending), do: "badge badge-warning badge-sm"

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <div class="max-w-3xl mx-auto">
        <div class="flex flex-col items-center gap-1 mb-4 sm:flex-row sm:justify-center sm:gap-2">
          <span class="flex items-center gap-2 text-center">
            <span class="hero-user-circle w-4 h-4 text-base-content/50 shrink-0"></span>
            <span class="text-xs text-base-content/60 break-all">Signed in as {@current_user_name} ({@current_user_email})</span>
          </span>
          <button type="button" $click="log_out_clicked" class="text-xs link link-primary shrink-0">Log Out</button>
        </div>

        <div class="flex items-center justify-center gap-3 mb-1">
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
          <h1 class="font-display text-xl sm:text-3xl text-center">
            {@current_user_name}'s Wedding Journey
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-2">
          Real curation status for every celebration in your catalog — the same films shown on the home page.
        </p>
        <div class="gold-divider w-24 mx-auto mb-8"></div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide text-center sm:text-left">Account Settings</h2>
              <div class="flex flex-col items-center text-center gap-2 mt-2 sm:flex-row sm:items-center sm:text-left sm:gap-3">
                {%if @current_user_avatar_url}
                  <img src={@current_user_avatar_url} alt="Profile photo" class="w-12 h-12 rounded-full object-cover border-2 border-primary/40 shrink-0" />
                {%else}
                  <div class="w-12 h-12 rounded-full bg-base-300 border-2 border-primary/20 flex items-center justify-center shrink-0">
                    <span class="hero-user w-6 h-6 text-base-content/40"></span>
                  </div>
                {/if}
                <div>
                  <p class="text-sm text-base-content/70 flex flex-wrap items-center justify-center gap-1.5 sm:justify-start">
                    {@current_user_name}
                    {%if @superuser?}
                      <span class="badge badge-secondary badge-sm gap-1">
                        <span class="hero-shield-check w-3 h-3"></span>
                        Superuser
                      </span>
                    {/if}
                  </p>
                  <p class="text-sm text-base-content/70 break-all">{@current_user_email}</p>
                </div>
              </div>
              {%if @current_user_phone}
                <p class="text-sm text-base-content/70 mt-2 flex items-center justify-center gap-1.5 sm:justify-start">
                  <span class="hero-phone w-3.5 h-3.5 text-base-content/40 shrink-0"></span>
                  {@current_user_phone}
                </p>
              {/if}
              {%if @current_user_wedding_date}
                <p class="text-sm text-base-content/70 mt-1 flex items-center justify-center gap-1.5 sm:justify-start">
                  <span class="hero-calendar w-3.5 h-3.5 text-base-content/40 shrink-0"></span>
                  {@current_user_wedding_date}
                </p>
              {/if}
              {%if @superuser?}
                <p class="text-sm text-base-content/70 mt-1 flex items-center justify-center gap-1.5 sm:justify-start">
                  <span class="hero-sparkles w-3.5 h-3.5 text-base-content/40 shrink-0"></span>
                  Access Tier: All Features Unlocked (Superuser)
                </p>
              {/if}
              <div class="mt-4 flex justify-center sm:justify-start">
                <Link to={AccountSettingsPage} class="btn btn-secondary btn-sm gap-2">
                  <span class="hero-cog-6-tooth w-4 h-4"></span>
                  Edit Account Settings
                </Link>
              </div>
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body items-center text-center">
              <div class="radial-progress text-primary" style={"--value:#{@completion_percentage}; --size:8rem; --thickness:0.7rem;"} role="progressbar">
                <span class="font-display text-2xl text-base-content">{@completion_percentage}%</span>
              </div>
              <p class="text-sm text-base-content/60 -mt-1">Complete</p>
              {%if @premium?}
                <span class="badge badge-success gap-1 mt-2">
                  <span class="hero-check-badge w-3.5 h-3.5"></span>
                  Premium Unlocked
                </span>
              {%else}
                <Link to={UpgradePage} class="btn btn-primary btn-sm mt-2">Get Premium</Link>
              {/if}
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">My Wedding Timeline Status</h2>
              <p class="text-sm text-base-content/70 mt-2">
                {@done_count} of {@total_count} celebrations fully curated.
              </p>
              {%if @next_movie_title}
                <p class="text-sm text-base-content/70 mt-1">
                  Next: finish curating &quot;{@next_movie_title}&quot;.
                </p>
              {%else}
                <p class="text-sm text-base-content/70 mt-1">
                  All caught up — nothing pending review.
                </p>
              {/if}
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">My Uploaded Event Videos</h2>
              <script>
                {%raw}
                (function () {
                  if (window.__dashboardMoviesPollAttached) { return; }
                  window.__dashboardMoviesPollAttached = true;

                  // The :movie_ingested broadcast (see this page's moduledoc)
                  // updates this list within about a second of ingestion
                  // finishing — this is only a fallback in case one is ever
                  // missed (e.g. the realtime connection dropped and
                  // reconnected in between), so it doesn't need to be
                  // frequent.
                  setInterval(function () {
                    Hologram.dispatchAction('movies_poll', 'page', {});
                  }, 15000);
                })();
                {/raw}
              </script>
              {%if @movies == []}
                <p class="text-sm text-base-content/60 mt-2">No videos uploaded yet.</p>
              {%else}
                <ul class="text-sm text-base-content/70 mt-2 flex flex-col gap-1.5">
                  {%for movie <- @movies}
                    <li class="flex items-center gap-2">
                      <span class={movie.badge_class}>{movie.badge_label}</span>
                      <Link to={PlayerPage, id: movie.id} class="hover:underline">{movie.title}</Link>
                    </li>
                  {/for}
                </ul>
              {/if}
              <div class="mt-4">
                <Link to={UploadPage} class="btn btn-primary btn-sm gap-2">
                  <span class="hero-cloud-arrow-up w-4 h-4"></span>
                  Upload More Videos
                </Link>
              </div>
            </div>
          </div>
        </div>

        <h2 class="font-display text-base text-center uppercase tracking-wide mt-8 mb-3">Quick Actions</h2>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <Link to={EditEventDetailsPage} class="btn btn-secondary btn-block h-auto py-3 flex-col gap-1">
            <span class="hero-pencil-square w-5 h-5"></span>
            <span class="text-xs">Edit Event Details</span>
          </Link>
          <Link to={InviteTeamPage} class="btn btn-secondary btn-block h-auto py-3 flex-col gap-1">
            <span class="hero-envelope w-5 h-5"></span>
            <span class="text-xs">Invite Team</span>
          </Link>
          <Link to={GenerateLinkPage} class="btn btn-secondary btn-block h-auto py-3 flex-col gap-1">
            <span class="hero-link w-5 h-5"></span>
            <span class="text-xs">Generate Shareable Link</span>
          </Link>
        </div>

        <p class="text-center text-sm text-base-content/70 mt-8">
          {%if @completion_percentage >= 100}
            Status: Complete
          {%else}
            Status: In Progress (curated to {@completion_percentage}%)
          {/if}
        </p>

        <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 mt-6 text-xs text-base-content/60">
          <span class="flex items-center gap-1">
            <span class="hero-shield-check w-4 h-4 text-primary"></span>
            Secure &amp; Private
          </span>
          <span class="flex items-center gap-1">
            <span class="hero-film w-4 h-4 text-primary"></span>
            Professional Curation
          </span>
          <span class="flex items-center gap-1">
            <span class="hero-link w-4 h-4 text-primary"></span>
            Custom Shareable Link
          </span>
        </div>
      </div>
    </div>
    """
  end
end
