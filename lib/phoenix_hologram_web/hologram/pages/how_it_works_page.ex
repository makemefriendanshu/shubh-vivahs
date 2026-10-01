defmodule PhoenixHologramWeb.Hologram.Pages.HowItWorksPage do
  @moduledoc """
  Explains the two ways to experience Shubh Vivahs: browsing/voting in the
  Premiere Hall as a viewer, and curating a film from its Admin View — plus
  how the Focus Engine turns raw footage into a "who's leading" scene poll.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias PhoenixHologramWeb.Hologram.Pages.AdminMoviesPage
  alias PhoenixHologramWeb.Hologram.Pages.PremierExperiencePage
  alias PhoenixHologramWeb.Hologram.Pages.PremierePage
  alias PhoenixHologramWeb.Hologram.Pages.PricingPage
  alias PhoenixHologramWeb.Hologram.Pages.ScienceOfFocusPage
  alias PhoenixHologramWeb.Hologram.Pages.UpgradePage

  route "/how-it-works"

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  @viewer_steps [
    %{
      icon: "hero-magnifying-glass",
      title: "Explore Celebrations",
      body: "Browse every public Shubh Vivahs wedding and celebration film in the Premiere Hall."
    },
    %{
      icon: "hero-video-camera",
      title: "Watch & Enjoy",
      body: "Play any film and relive the moments exactly as the event happened."
    },
    %{
      icon: "hero-viewfinder-circle",
      title: "See Who's In Focus",
      body: "As the video plays, the scene tracker shows who the AI recognises on screen."
    },
    %{
      icon: "hero-trophy",
      title: "Vote For The Leading Face",
      body: "Cast a vote for anyone in the scene — the face with the most votes is marked \"Leading\"."
    }
  ]

  @admin_steps [
    %{
      icon: "hero-key",
      title: "Open Admin View",
      body: "Switch to Admin View on any film to see the full scene-by-scene breakdown."
    },
    %{
      icon: "hero-pencil-square",
      title: "Edit Event Details",
      body: "Rename the film and set its description, event date, and location."
    },
    %{
      icon: "hero-users",
      title: "Manage Recognised Faces",
      body: "Review every unique face the AI clustered, with its own thumbnail and timestamps."
    },
    %{
      icon: "hero-adjustments-horizontal",
      title: "Watch The Votes Live",
      body: "Follow viewer votes update in real time as the leading face for each scene shifts."
    }
  ]

  @engine_steps [
    %{label: "Video Stream", icon: "hero-video-camera"},
    %{label: "Face Detection (AI)", icon: "hero-face-smile"},
    %{label: "Face Clustering (AI)", icon: "hero-square-3-stack-3d"},
    %{label: "Scene Timeline", icon: "hero-film"},
    %{label: "Viewer Voting", icon: "hero-hand-raised"},
    %{label: "Leading Face", icon: "hero-trophy"}
  ]

  def init(_params, component, _server) do
    component
    |> put_state(:viewer_steps, @viewer_steps)
    |> put_state(:admin_steps, @admin_steps)
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
            How It Works: Your Guide To Celebration
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-2">
          Every film has two sides — watch and vote as a guest, or curate it from behind the scenes.
        </p>
        <div class="gold-divider w-24 mx-auto mb-8"></div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div>
            <h2 class="font-display text-lg text-center mb-4 badge badge-lg badge-outline badge-primary px-6 py-4 w-full">
              The Viewer Experience
            </h2>
            <div class="flex flex-col gap-4">
              {%for {step, index} <- Enum.with_index(@viewer_steps, 1)}
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
              The Admin View
            </h2>
            <div class="flex flex-col gap-4">
              {%for {step, index} <- Enum.with_index(@admin_steps, 1)}
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
              <Link to={AdminMoviesPage} class="btn btn-secondary btn-sm">Open Admin View</Link>
            </div>
            <p class="text-center text-xs mt-2">
              <Link to={PricingPage} class="link link-hover">See the pricing bands that unlock it &rarr;</Link>
            </p>
            <p class="text-center text-xs mt-1">
              <Link to={UpgradePage} class="link link-hover">Already curating? See the Premium upgrade &rarr;</Link>
            </p>
          </div>
        </div>

        <div class="mt-10 card card-stock shadow-xl">
          <div class="card-body">
            <h2 class="font-display text-lg text-center">The Focus Engine</h2>
            <p class="text-center text-sm text-base-content/60 -mt-1 mb-1">The pipeline behind "who's leading" every scene</p>
            <p class="text-center text-xs mb-4">
              <Link to={ScienceOfFocusPage} class="link link-hover">Read the science behind it &rarr;</Link>
            </p>
            <div class="gold-divider w-16 mx-auto mb-6"></div>

            <div class="flex flex-wrap items-center justify-center gap-2 sm:gap-3">
              {%for {step, index} <- Enum.with_index(@engine_steps)}
                <div class="flex flex-col items-center gap-2 bg-secondary text-secondary-content rounded-box px-3 py-3 w-28 text-center">
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
          <Link to={PremierExperiencePage} class="link link-hover text-sm">
            See streaming, downloads &amp; community tools &rarr;
          </Link>
        </div>
      </div>
    </div>
    """
  end
end
