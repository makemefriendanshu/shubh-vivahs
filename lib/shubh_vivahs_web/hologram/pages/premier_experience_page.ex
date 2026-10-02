defmodule ShubhVivahsWeb.Hologram.Pages.PremierExperiencePage do
  @moduledoc """
  Sells the two extra layers on top of a plain watch: streaming/downloads
  in whichever quality suits your connection, and the community layer
  (cast recognition voting, likes, comments) built on `Engagement` and
  `FocusPoll`.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias ShubhVivahsWeb.Hologram.Pages.HowItWorksPage
  alias ShubhVivahsWeb.Hologram.Pages.PremierePage
  alias ShubhVivahsWeb.Hologram.Pages.ScienceOfFocusPage

  route "/premier-experience"

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  @streaming_steps [
    %{
      icon: "hero-signal",
      title: "Multi-Quality Viewing",
      body: "Choose Original, Data Saver, or Minimal quality for smooth streaming on any device."
    },
    %{
      icon: "hero-arrow-down-tray",
      title: "Download In Your Quality",
      body: "Save a copy in whichever quality you're watching, to keep or share."
    },
    %{
      icon: "hero-queue-list",
      title: "Download By Part",
      body: "Grab the film in manageable segments — ideal for slower connections."
    },
    %{
      icon: "hero-play-circle",
      title: "Play In Parts",
      body: "Stream part-by-part without downloading, and resume exactly where you left off."
    }
  ]

  @community_steps [
    %{
      icon: "hero-check-badge",
      title: "Cast Recognition Voting",
      body: "Help confirm which celebration cast members are in the spotlight of each scene."
    },
    %{
      icon: "hero-trophy",
      title: "AI & Community Focus Winner",
      body: "The AI's face recognition plus everyone's votes crown a \"leading\" face for each scene."
    },
    %{
      icon: "hero-heart",
      title: "Like Your Favourite Moments",
      body: "Tap like on a film to show it some love — and see how many others felt the same."
    },
    %{
      icon: "hero-chat-bubble-left-right",
      title: "Leave Memory-Filled Comments",
      body: "Share a memory or message for the hosts and family, right on the film."
    }
  ]

  @engine_steps [
    %{label: "Video Stream", icon: "hero-video-camera"},
    %{label: "Scene Analysis (AI)", icon: "hero-viewfinder-circle"},
    %{label: "Cast Recognition (AI & Votes)", icon: "hero-check-badge"},
    %{label: "Engagement (Likes, Comments, Votes)", icon: "hero-chat-bubble-left-right"},
    %{label: "Focus/Winner Final Display", icon: "hero-trophy"}
  ]

  def init(_params, component, _server) do
    component
    |> put_state(:streaming_steps, @streaming_steps)
    |> put_state(:community_steps, @community_steps)
    |> put_state(:engine_steps, @engine_steps)
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
            Explore Your Premier Celebration Tools
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-2">
          Making memories easier to watch, keep, and celebrate together.
        </p>
        <div class="gold-divider w-24 mx-auto mb-8"></div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div>
            <h2 class="font-display text-lg text-center mb-4 badge badge-lg badge-outline badge-primary px-6 py-4 w-full">
              Streaming &amp; Downloads
            </h2>
            <div class="flex flex-col gap-4">
              {%for {step, index} <- Enum.with_index(@streaming_steps, 1)}
                <div class="card card-stock shadow-xl">
                  <div class="card-body flex-row items-center gap-4 py-4">
                    <div class="relative shrink-0">
                      <div class="w-14 h-14 rounded-box bg-primary/10 border-2 border-primary/40 flex items-center justify-center">
                        <span class={"#{step.icon} w-7 h-7 text-primary"}></span>
                      </div>
                      <span class="absolute -top-2 -left-2 w-6 h-6 rounded-full bg-primary text-primary-content font-display text-xs flex items-center justify-center shadow ring-2 ring-base-100">
                        {index}
                      </span>
                    </div>
                    <div>
                      <p class="font-display text-sm uppercase tracking-wide">{step.title}</p>
                      <p class="text-sm text-base-content/70 mt-1">{step.body}</p>
                    </div>
                  </div>
                </div>
              {/for}
            </div>
            <div class="text-center mt-4">
              <Link to={PremierePage} class="btn btn-primary btn-sm">Visit The Premiere Hall</Link>
            </div>
          </div>

          <div>
            <h2 class="font-display text-lg text-center mb-4 badge badge-lg bg-secondary text-secondary-content border-secondary px-6 py-4 w-full">
              Community &amp; Recognition
            </h2>
            <div class="flex flex-col gap-4">
              {%for {step, index} <- Enum.with_index(@community_steps, 1)}
                <div class="card card-stock shadow-xl">
                  <div class="card-body flex-row items-center gap-4 py-4">
                    <div class="relative shrink-0">
                      <div class="w-14 h-14 rounded-box bg-secondary/10 border-2 border-secondary/40 flex items-center justify-center">
                        <span class={"#{step.icon} w-7 h-7 text-secondary"}></span>
                      </div>
                      <span class="absolute -top-2 -left-2 w-6 h-6 rounded-full bg-secondary text-secondary-content font-display text-xs flex items-center justify-center shadow ring-2 ring-base-100">
                        {index}
                      </span>
                    </div>
                    <div>
                      <p class="font-display text-sm uppercase tracking-wide">{step.title}</p>
                      <p class="text-sm text-base-content/70 mt-1">{step.body}</p>
                    </div>
                  </div>
                </div>
              {/for}
            </div>
            <div class="text-center mt-4">
              <Link to={PremierePage} class="btn btn-secondary btn-sm">Start Watching &amp; Voting</Link>
            </div>
          </div>
        </div>

        <div class="mt-10 card card-stock shadow-xl">
          <div class="card-body">
            <h2 class="font-display text-lg text-center">The Premiere Experience</h2>
            <p class="text-center text-sm text-base-content/60 -mt-1 mb-1">Powered by AI &amp; community voting</p>
            <p class="text-center text-xs mb-4">
              <Link to={ScienceOfFocusPage} class="link link-hover">Read the science behind it &rarr;</Link>
            </p>
            <div class="gold-divider w-16 mx-auto mb-6"></div>

            <div class="flex flex-wrap items-center justify-center gap-2 sm:gap-3">
              {%for {step, index} <- Enum.with_index(@engine_steps)}
                <div class="flex flex-col items-center gap-2 bg-secondary text-secondary-content rounded-box px-3 py-3 w-32 text-center">
                  <span class={"#{step.icon} w-6 h-6"}></span>
                  <span class="font-display text-[0.65rem] tracking-wide uppercase">{step.label}</span>
                </div>
                {%if index < length(@engine_steps) - 1}
                  <span class="text-primary text-xl shrink-0">&rarr;</span>
                {/if}
              {/for}
            </div>
          </div>
        </div>

        <div class="text-center mt-6">
          <Link to={HowItWorksPage} class="link link-hover text-sm">
            See the full guide to browsing, admin &amp; scene focus &rarr;
          </Link>
        </div>
      </div>
    </div>
    """
  end
end
