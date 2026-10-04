defmodule ShubhVivahsWeb.Hologram.Pages.SentInvitationsPage do
  @moduledoc """
  Visual "manage sent invitations" page only, shown with sample data
  (one pending, one accepted, one expired invitation), matching
  InviteTeamPage's approach — there is no team/invite system in the app
  yet (no resend/revoke logic beyond what's shown here). Reached from
  InviteTeamPage's "Manage Sent Invitations" link, which was previously
  decorative.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias ShubhVivahsWeb.Hologram.Pages.DashboardPage
  alias ShubhVivahsWeb.Hologram.Pages.InviteTeamPage

  @invitations [
    %{
      email: "priya.friend@example.com",
      status: "Pending",
      badge: "badge-warning",
      detail: "Sent 2 days ago"
    },
    %{
      email: "media.assistant@example.com",
      status: "Accepted",
      badge: "badge-success",
      detail: "Joined as Media Team"
    },
    %{
      email: "old.contact@example.com",
      status: "Expired",
      badge: "badge-error",
      detail: "Sent 15 days ago"
    }
  ]

  route "/sent-invitations"

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :invitations, @invitations)
  end

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
            Manage Sent Invitations
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-2">
          A preview of how you'll track and manage invitations you've sent.
        </p>
        <div class="gold-divider w-24 mx-auto mb-6"></div>

        <div class="card card-stock shadow-xl mb-6">
          <div class="card-body">
            <h2 class="font-display text-base uppercase tracking-wide">Sent Invitations</h2>
            <ul class="flex flex-col gap-2 mt-3">
              {%for invitation <- @invitations}
                <li class="flex flex-wrap items-center justify-between gap-2 rounded-box border border-base-content/10 px-3 py-2">
                  <div class="min-w-0">
                    <p class="text-sm break-all">{invitation.email}</p>
                    <p class="text-xs text-base-content/50">{invitation.detail}</p>
                  </div>
                  <div class="flex items-center gap-2 shrink-0">
                    <span class={"badge badge-sm #{invitation.badge}"}>{invitation.status}</span>
                    <span class="btn btn-xs btn-outline pointer-events-none">Resend</span>
                    <span class="btn btn-xs btn-error btn-outline pointer-events-none">Revoke</span>
                  </div>
                </li>
              {/for}
            </ul>
          </div>
        </div>

        <div class="flex flex-col items-center gap-3">
          <Link to={InviteTeamPage} class="btn btn-outline btn-block gap-2">
            <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
            Back To Invite Team
          </Link>
          <Link to={DashboardPage} class="link link-hover text-sm">Back To Dashboard</Link>
        </div>
        <p class="text-center text-xs text-base-content/50 mt-3">
          Resending and revoking aren't wired up yet — everything above is a preview of the feature.
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
