defmodule ShubhVivahsWeb.Hologram.Pages.InviteTeamPage do
  @moduledoc """
  Visual "invite team members" page only, shown with sample data (Rahul,
  Priya, and a "Media Team" member already on the team; 5 of 10
  invitations remaining), matching DashboardPage/GenerateLinkPage's
  approach — there is no team/invite system in the app yet (no email
  sending, no member roles or permissions beyond what's shown here).
  Replaces the decorative, pointer-events-none "Invite Team" quick
  action on DashboardPage with a real destination.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias ShubhVivahsWeb.Hologram.Pages.DashboardPage
  alias ShubhVivahsWeb.Hologram.Pages.SentInvitationsPage

  route "/invite-team"

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
            Invite Team Members (Premium Portal)
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-2">
          A preview of how you'll add collaborators to help curate your wedding films.
        </p>
        <div class="gold-divider w-24 mx-auto mb-6"></div>

        <div class="card card-stock shadow-xl mb-6">
          <div class="card-body">
            <h2 class="font-display text-base uppercase tracking-wide">Current Team Members</h2>
            <ul class="flex flex-col gap-2 mt-3">
              <li class="flex items-center justify-between rounded-box border border-base-content/10 px-3 py-2">
                <span class="flex items-center gap-2 text-sm">
                  <span class="hero-user-circle w-5 h-5 text-primary"></span>
                  Rahul P.
                </span>
                <span class="hero-cog-6-tooth w-4 h-4 text-base-content/40"></span>
              </li>
              <li class="flex items-center justify-between rounded-box border border-base-content/10 px-3 py-2">
                <span class="flex items-center gap-2 text-sm">
                  <span class="hero-user-circle w-5 h-5 text-primary"></span>
                  Priya S.
                </span>
                <span class="hero-cog-6-tooth w-4 h-4 text-base-content/40"></span>
              </li>
              <li class="flex items-center justify-between rounded-box border border-base-content/10 px-3 py-2">
                <span class="flex items-center gap-2 text-sm">
                  <span class="hero-video-camera w-5 h-5 text-primary"></span>
                  Media Team
                </span>
                <span class="hero-cog-6-tooth w-4 h-4 text-base-content/40"></span>
              </li>
            </ul>
          </div>
        </div>

        <div class="card card-stock shadow-xl mb-6">
          <div class="card-body">
            <h2 class="font-display text-base uppercase tracking-wide">Invite New Member</h2>

            <div class="mt-4">
              <label class="text-xs uppercase tracking-wide text-base-content/50">Email Address</label>
              <input
                type="email"
                class="input input-bordered input-sm w-full mt-1"
                placeholder="Email Address"
                disabled
              />
            </div>

            <div class="mt-4">
              <label class="text-xs uppercase tracking-wide text-base-content/50">Optional Invitation Message</label>
              <textarea
                class="textarea textarea-bordered w-full mt-1 text-sm"
                placeholder="Optional Invitation Message"
                disabled
              ></textarea>
            </div>

            <div class="rounded-box border border-base-content/10 px-3 py-2 mt-4">
              <p class="text-xs uppercase tracking-wide text-base-content/50">Invitation Limits</p>
              <p class="text-sm mt-1">Remaining Invitations: 5 of 10</p>
              <progress class="progress progress-primary w-full mt-1" value="5" max="10"></progress>
            </div>

            <span class="btn btn-primary btn-block gap-2 pointer-events-none mt-6">
              <span class="hero-paper-airplane w-4 h-4"></span>
              Send Invitation(s)
            </span>
            <p class="text-center text-xs text-base-content/50 mt-2">
              <Link to={SentInvitationsPage} class="link link-hover">Manage Sent Invitations</Link>
            </p>
          </div>
        </div>

        <div class="flex flex-col items-center gap-3">
          <Link to={DashboardPage} class="btn btn-outline btn-block gap-2">
            <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
            Back To Dashboard
          </Link>
        </div>
        <p class="text-center text-xs text-base-content/50 mt-3">
          Team invites aren't wired up yet — everything above is a preview of the feature.
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
