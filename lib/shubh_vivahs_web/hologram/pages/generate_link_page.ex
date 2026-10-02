defmodule ShubhVivahsWeb.Hologram.Pages.GenerateLinkPage do
  @moduledoc """
  Visual "generate a shareable link" page only, shown with sample data
  (a fixed link, one already-active share), matching DashboardPage and
  UploadPage's approach — there is no link/share system in the app yet
  (no password protection, expiry, or download controls beyond what's
  shown here). The bottom actions link to real destinations that
  already exist (Dashboard) rather than a fake share flow that goes
  nowhere.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias ShubhVivahsWeb.Hologram.Pages.DashboardPage

  route "/share"

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
            Generate Shareable Link (Legacy Preview)
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-2">
          A preview of what sharing your wedding films will look like once it is built.
        </p>
        <div class="gold-divider w-24 mx-auto mb-6"></div>

        <div class="card card-stock shadow-xl mb-6">
          <div class="card-body">
            <h2 class="font-display text-base uppercase tracking-wide">Configure Your Shareable Link</h2>

            <div class="mt-4">
              <label class="text-xs uppercase tracking-wide text-base-content/50">Customize Link (Optional)</label>
              <div class="flex flex-wrap items-center gap-2 mt-1">
                <input
                  type="text"
                  class="input input-bordered input-sm flex-1 min-w-0"
                  value="https://shubhvivahs.com/rahul-priya-wedding"
                  disabled
                />
                <span class="link link-hover text-xs text-base-content/50">Check Availability</span>
              </div>
            </div>

            <div class="flex items-center justify-between mt-5">
              <span class="flex items-center gap-2 text-sm font-display">
                <span class="hero-lock-open w-4 h-4"></span>
                Password Protect
              </span>
              <input type="checkbox" class="toggle toggle-primary pointer-events-none" checked />
            </div>
            <input
              type="password"
              class="input input-bordered input-sm w-full mt-2"
              value="wedding2026"
              disabled
            />

            <div class="flex items-center justify-between mt-5">
              <span class="flex items-center gap-2 text-sm font-display">
                <span class="hero-clock w-4 h-4"></span>
                Expirable Link
              </span>
              <input type="checkbox" class="toggle toggle-primary pointer-events-none" checked />
            </div>
            <div class="grid grid-cols-2 gap-2 mt-2">
              <div>
                <label class="text-xs uppercase tracking-wide text-base-content/50">Expiry Date</label>
                <input type="text" class="input input-bordered input-sm w-full mt-1" value="17 Dec 2026" disabled />
              </div>
              <div>
                <label class="text-xs uppercase tracking-wide text-base-content/50">Time</label>
                <input type="text" class="input input-bordered input-sm w-full mt-1" value="10:00 AM" disabled />
              </div>
            </div>

            <div class="flex items-center justify-between mt-5">
              <span class="flex items-center gap-2 text-sm font-display">
                <span class="hero-arrow-down-tray w-4 h-4"></span>
                Allow Guest Downloads
              </span>
              <input type="checkbox" class="toggle toggle-primary pointer-events-none" />
            </div>

            <div class="flex items-center justify-between mt-5">
              <span class="flex items-center gap-2 text-sm font-display">
                <span class="hero-chat-bubble-left-right w-4 h-4"></span>
                Private Message
              </span>
              <input type="checkbox" class="toggle toggle-primary pointer-events-none" />
            </div>
            <textarea
              class="textarea textarea-bordered w-full mt-2 text-sm"
              placeholder="Add a personalized message for your guests"
              disabled
            ></textarea>

            <span class="btn btn-primary btn-block gap-2 pointer-events-none mt-6">
              <span class="hero-link w-4 h-4"></span>
              Generate Premium Shareable Link
            </span>
            <p class="text-center text-xs text-base-content/50 mt-2">
              <span class="link link-hover">Share via External Platforms (e.g., WhatsApp, Email)</span>
            </p>
          </div>
        </div>

        <div class="card card-stock shadow-xl mb-6">
          <div class="card-body">
            <h2 class="font-display text-base uppercase tracking-wide">Your Active Shareable Links</h2>
            <div class="flex flex-wrap items-center gap-2 mt-2 text-sm">
              <span class="hero-link w-4 h-4 text-primary shrink-0"></span>
              <span class="text-base-content/70 break-all">shubhvivahs.com/rahul-priya-wedding</span>
              <span class="badge badge-success badge-sm">Active</span>
              <div class="flex gap-2 ml-auto">
                <span class="btn btn-xs btn-outline pointer-events-none">Copy Link</span>
                <span class="btn btn-xs btn-error btn-outline pointer-events-none">Revoke</span>
              </div>
            </div>
          </div>
        </div>

        <div class="flex flex-col items-center gap-3">
          <Link to={DashboardPage} class="btn btn-outline btn-block gap-2">
            <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
            Back To Dashboard
          </Link>
        </div>
        <p class="text-center text-xs text-base-content/50 mt-3">
          Link sharing isn't wired up yet — everything above is a preview of the feature.
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
