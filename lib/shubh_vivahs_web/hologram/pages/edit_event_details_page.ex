defmodule ShubhVivahsWeb.Hologram.Pages.EditEventDetailsPage do
  @moduledoc """
  Visual "edit event details" page only, shown with sample data (Rahul
  & Priya's vivah, 15 Oct 2023 at The Imperial Hotel, 350 guests),
  matching DashboardPage/InviteTeamPage/GenerateLinkPage's approach —
  there is no event-editing system in the app yet (no photo upload,
  custom domain, or save/discard logic beyond what's shown here).
  Replaces the "Edit Event Details" quick action on DashboardPage,
  which previously pointed at AdminMoviesPage (a real page, but the
  gallery/faces admin view, not an event-details editor).
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias ShubhVivahsWeb.Hologram.Pages.DashboardPage

  route "/edit-event-details"

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <div class="max-w-2xl mx-auto">
        <div class="flex items-center justify-center gap-2 mb-4">
          <span class="hero-user-circle w-4 h-4 text-base-content/50"></span>
          <span class="text-xs text-base-content/60">Signed in as Rahul P. &amp; Priya S. (sample account)</span>
        </div>

        <div class="flex items-center justify-center gap-3 mb-1">
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
          <h1 class="font-display text-xl sm:text-2xl text-center">
            Edit Event Details (Premium Portal)
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-xs text-base-content/50 mb-2">
          <Link to={DashboardPage} class="link link-hover">Dashboard</Link>
          &gt; My Vivah &gt; <span class="text-base-content/70">Edit Details</span>
        </p>
        <p class="text-center text-sm text-base-content/60 mb-2">
          A preview of what editing your event details will look like once it is built.
        </p>
        <div class="gold-divider w-24 mx-auto mb-6"></div>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-6">
          <div class="sm:col-span-2 card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">Vivah Information</h2>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Event Title</label>
                <input
                  type="text"
                  class="input input-bordered input-sm w-full mt-1"
                  value="Rahul P. &amp; Priya S. Legacy Vivah"
                  disabled
                />
              </div>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Date &amp; Time</label>
                <input
                  type="text"
                  class="input input-bordered input-sm w-full mt-1"
                  value="15 Oct 2023, 10:00 AM"
                  disabled
                />
              </div>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Location</label>
                <input
                  type="text"
                  class="input input-bordered input-sm w-full mt-1"
                  value="The Imperial Hotel, New Delhi"
                  disabled
                />
              </div>

              <h2 class="font-display text-base uppercase tracking-wide mt-6">Guest Details</h2>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Estimated Guest Count</label>
                <input type="text" class="input input-bordered input-sm w-full mt-1" value="350" disabled />
              </div>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Private Access Notes for Family</label>
                <textarea
                  class="textarea textarea-bordered w-full mt-1 text-sm"
                  placeholder="Add private notes for family members"
                  disabled
                ></textarea>
              </div>

              <span class="btn btn-primary btn-block gap-2 pointer-events-none mt-6">
                <span class="hero-check-circle w-4 h-4"></span>
                Save All Changes &amp; Update My Vivah
              </span>
              <Link to={DashboardPage} class="btn btn-outline btn-block gap-2 mt-2">
                <span class="hero-x-circle w-4 h-4"></span>
                Discard Changes &amp; Exit Portal
              </Link>
            </div>
          </div>

          <div class="card card-stock shadow-xl h-fit">
            <div class="card-body">
              <h2 class="font-display text-sm uppercase tracking-wide">Quick Updates</h2>

              <p class="text-xs uppercase tracking-wide text-base-content/50 mt-4">Change Event Photo</p>
              <span class="btn btn-outline btn-sm gap-2 pointer-events-none mt-1">
                <span class="hero-arrow-up-tray w-4 h-4"></span>
                Upload
              </span>

              <p class="text-xs uppercase tracking-wide text-base-content/50 mt-4">Edit Custom Domain</p>
              <input
                type="text"
                class="input input-bordered input-sm w-full mt-1"
                value="RahulAndPriya.com"
                disabled
              />
            </div>
          </div>
        </div>

        <div class="flex flex-col items-center gap-3 mt-6">
          <Link to={DashboardPage} class="btn btn-outline btn-block gap-2">
            <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
            Back To Dashboard
          </Link>
        </div>
        <p class="text-center text-xs text-base-content/50 mt-3">
          Editing isn't wired up yet — everything above is a preview of the feature.
        </p>

        <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 mt-8 text-xs text-base-content/60">
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
