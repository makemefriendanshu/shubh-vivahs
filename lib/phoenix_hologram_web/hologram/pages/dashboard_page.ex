defmodule PhoenixHologramWeb.Hologram.Pages.DashboardPage do
  @moduledoc """
  "My account" dashboard, gated behind `RequireAuthenticatedUser` — an
  anonymous visitor is redirected to LoginPage before this ever renders.
  The signed-in identity (name/email, Log Out) is real, backed by
  `PhoenixHologram.Accounts`; the wedding-journey content below it (a
  65%-curated timeline, sample uploaded videos) is still sample data,
  since there is no per-couple wedding/event data model in the app yet.
  Buttons that have a genuine destination in the app today (Edit Event
  Details, Pricing, Generate Shareable Link, Invite Team) link there
  for real; the rest ("View Timeline Preview") are decorative, matching
  how PricingPage handles features with no backend yet.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias PhoenixHologramWeb.Hologram.Middleware.RequireAuthenticatedUser
  alias PhoenixHologramWeb.Hologram.Pages.EditEventDetailsPage
  alias PhoenixHologramWeb.Hologram.Pages.GenerateLinkPage
  alias PhoenixHologramWeb.Hologram.Pages.InviteTeamPage
  alias PhoenixHologramWeb.Hologram.Pages.UpgradePage
  alias PhoenixHologramWeb.Hologram.Pages.UploadPage

  route "/dashboard"

  middleware RequireAuthenticatedUser

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server) do
    # Extracted into plain strings rather than putting the raw
    # `Accounts.User` Ecto struct into template state — that duplicated
    # the email on the client after hydration (worked fine in the initial
    # server-rendered HTML, so it's a client-side quirk specific to
    # rendering Ecto struct fields, not present with plain maps/strings
    # elsewhere in this app).
    user = get_stash(server, :current_user)
    put_state(component, current_user_name: user.name, current_user_email: user.email)
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

  def command(:log_out, _params, server) do
    server
    |> delete_user_id()
    |> put_action(:logged_out)
  end

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <div class="max-w-3xl mx-auto">
        <div class="flex items-center justify-center gap-2 mb-4">
          <span class="hero-user-circle w-4 h-4 text-base-content/50"></span>
          <span class="text-xs text-base-content/60">Signed in as {@current_user_name} ({@current_user_email})</span>
          <button type="button" $click="log_out_clicked" class="text-xs link link-primary">Log Out</button>
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
          A preview of what every couple's dashboard will look like — the wedding timeline below is sample content.
        </p>
        <div class="gold-divider w-24 mx-auto mb-8"></div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
          <div class="card card-stock shadow-xl">
            <div class="card-body items-center text-center">
              <div class="radial-progress text-primary" style="--value:65; --size:8rem; --thickness:0.7rem;" role="progressbar">
                <span class="font-display text-2xl text-base-content">65%</span>
              </div>
              <p class="text-sm text-base-content/60 -mt-1">Complete</p>
              <Link to={UpgradePage} class="btn btn-primary btn-sm mt-2">Get Premium</Link>
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">My Wedding Timeline Status</h2>
              <p class="text-sm text-base-content/70 mt-2">
                Your unique timeline is being curated.
              </p>
              <p class="text-sm text-base-content/70 mt-1">
                Next: add Sangeet &amp; Reception descriptions.
              </p>
            </div>
          </div>
        </div>

        <div class="mt-6 card card-stock shadow-xl">
          <div class="card-body">
            <h2 class="font-display text-base uppercase tracking-wide">My Uploaded Event Videos</h2>
            <ul class="text-sm text-base-content/70 mt-2 flex flex-col gap-1.5">
              <li class="flex items-center gap-2">
                <span class="badge badge-warning badge-sm">Pending Review</span>
                Sangeet
              </li>
              <li class="flex items-center gap-2">
                <span class="badge badge-success badge-sm">Upload Complete</span>
                Reception
              </li>
            </ul>
            <div class="mt-4">
              <Link to={UploadPage} class="btn btn-primary btn-sm gap-2">
                <span class="hero-cloud-arrow-up w-4 h-4"></span>
                Upload More Videos
              </Link>
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
          Status: In Progress (curated to 65%)
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
