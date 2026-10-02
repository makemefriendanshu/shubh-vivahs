defmodule ShubhVivahsWeb.Hologram.Pages.PricingPage do
  @moduledoc """
  Lays out the four Admin View pricing bands (Standard/Silver/Gold/Platinum)
  by video count, storage, and total runtime, and explains what Admin View
  itself unlocks (see `HowItWorksPage`'s `@admin_steps` for the source of
  that copy). No checkout or referral backend exists yet, so "Select Band"
  is presentational only — a real purchase flow is future work.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias ShubhVivahsWeb.Hologram.Pages.AdminMoviesPage
  alias ShubhVivahsWeb.Hologram.Pages.HowItWorksPage
  alias ShubhVivahsWeb.Hologram.Pages.UpgradePage

  route "/pricing"

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout, banner: :pricing

  @bands [
    %{
      tier: "Band-I",
      name: "Standard",
      icon: "hero-shield-check",
      badge_class: "badge-outline badge-primary",
      icon_wrap_class: "bg-primary/10 border-2 border-primary/40",
      icon_class: "text-primary",
      videos: "Up to 5",
      storage: "Up to 10GB",
      length: "Up to 5 hours",
      cost: "₹501"
    },
    %{
      tier: "Band-II",
      name: "Silver",
      icon: "hero-star",
      badge_class: "bg-base-300 text-base-content border-base-300",
      icon_wrap_class: "bg-base-300/60 border-2 border-base-300",
      icon_class: "text-base-content/70",
      videos: "Up to 20",
      storage: "Up to 50GB",
      length: "Up to 20 hours",
      cost: "₹1,501"
    },
    %{
      tier: "Band-III",
      name: "Gold",
      icon: "hero-sparkles",
      badge_class: "bg-primary text-primary-content border-primary",
      icon_wrap_class: "bg-primary/10 border-2 border-primary/40",
      icon_class: "text-primary",
      videos: "Up to 50",
      storage: "Up to 150GB",
      length: "Up to 50 hours",
      cost: "₹3,501"
    },
    %{
      tier: "Band-IV",
      name: "Platinum",
      icon: "hero-trophy",
      badge_class: "bg-secondary text-secondary-content border-secondary",
      icon_wrap_class: "bg-secondary/10 border-2 border-secondary/40",
      icon_class: "text-secondary",
      videos: "Up to 100",
      storage: "Up to 300GB",
      length: "Up to 100 hours",
      cost: "₹6,001"
    }
  ]

  def init(_params, component, _server) do
    put_state(component, :bands, @bands)
  end

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <div class="max-w-5xl mx-auto">
        <div class="flex items-center justify-center gap-3 mb-1">
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
          <h1 class="font-display text-xl sm:text-3xl text-center">
            Pricing: Unlock Admin View
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-2">
          Pick a band by how many films you'll curate — video count, storage, and total runtime.
        </p>
        <div class="gold-divider w-24 mx-auto mb-8"></div>

        <div id="bands" class="grid grid-cols-1 sm:grid-cols-2 gap-6 scroll-mt-6">
          {%for band <- @bands}
            <div class="card card-stock shadow-xl">
              <div class="card-body">
                <div class="flex items-center gap-3">
                  <div class={"w-14 h-14 rounded-box flex items-center justify-center shrink-0 #{band.icon_wrap_class}"}>
                    <span class={"#{band.icon} w-7 h-7 #{band.icon_class}"}></span>
                  </div>
                  <div>
                    <p class="text-xs text-base-content/50">{band.tier}</p>
                    <p class={"badge badge-lg #{band.badge_class}"}>{band.name}</p>
                  </div>
                </div>

                <ul class="text-sm text-base-content/70 mt-4 flex flex-col gap-1.5">
                  <li class="flex items-center gap-2">
                    <span class="hero-film w-4 h-4 shrink-0 text-base-content/40"></span>
                    Number of videos: {band.videos}
                  </li>
                  <li class="flex items-center gap-2">
                    <span class="hero-circle-stack w-4 h-4 shrink-0 text-base-content/40"></span>
                    Total storage: {band.storage}
                  </li>
                  <li class="flex items-center gap-2">
                    <span class="hero-clock w-4 h-4 shrink-0 text-base-content/40"></span>
                    Total video length: {band.length}
                  </li>
                </ul>

                <div class="gold-divider my-4"></div>

                <div class="flex items-center justify-between gap-3">
                  <p class="font-display text-2xl">{band.cost}</p>
                  <span class="btn btn-primary btn-sm pointer-events-none">Select Band</span>
                </div>
              </div>
            </div>
          {/for}
        </div>
        <p class="text-center text-xs text-base-content/50 mt-4">
          Online purchasing is coming soon — the bands above show what each level unlocks.
        </p>

        <div class="mt-10 card card-stock shadow-xl">
          <div class="card-body">
            <div class="flex items-start gap-4">
              <div class="w-12 h-12 shrink-0 rounded-box bg-secondary/10 border-2 border-secondary/40 flex items-center justify-center">
                <span class="hero-key w-6 h-6 text-secondary"></span>
              </div>
              <div>
                <h2 class="font-display text-base uppercase tracking-wide">Admin Facility Benefits</h2>
                <p class="text-sm text-base-content/70 mt-2">
                  With Admin View you can rename a film and edit its event details, manage every recognised face with its own thumbnail and timestamps, and follow the votes live as the leading face for each scene shifts.
                </p>
              </div>
            </div>
            <div class="text-center mt-4">
              <Link to={AdminMoviesPage} class="btn btn-secondary btn-sm">Open Admin View</Link>
            </div>
          </div>
        </div>

        <div class="mt-6 card bg-secondary text-secondary-content shadow-xl">
          <div class="card-body items-center text-center">
            <span class="hero-gift w-8 h-8"></span>
            <h2 class="font-display text-lg">Founder's Circle</h2>
            <p class="text-sm opacity-90 max-w-xl">
              Known friends, family, and past clients of the founder receive the Band-I (Standard) plan at no cost.
            </p>
            <a
              href="https://wa.me/919880538028"
              target="_blank"
              rel="noopener noreferrer"
              class="btn btn-primary btn-sm mt-2 gap-2"
            >
              <span class="hero-chat-bubble-left-right w-4 h-4"></span>
              Message The Founder On WhatsApp
            </a>
          </div>
        </div>

        <div class="text-center mt-6 flex flex-col gap-2">
          <Link to={UpgradePage} class="link link-hover text-sm">
            Already have an account? See the Premium upgrade instead &rarr;
          </Link>
          <Link to={HowItWorksPage} class="link link-hover text-sm">
            See the full guide to browsing, admin &amp; scene focus &rarr;
          </Link>
        </div>
      </div>
    </div>
    """
  end
end
