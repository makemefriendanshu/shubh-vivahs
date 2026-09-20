defmodule PhoenixHologramWeb.Hologram.Pages.HomePage do
  @moduledoc """
  Public landing page: sells the "turn your wedding videos into a digital
  keepsake" pitch, showcases the real films already in the Premiere Hall as
  a live example, and offers Log In / Register tabs (visual-only, same as
  `LoginPage` / `RegisterPage`, until a real auth system is built) to start
  a story.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias PhoenixHologram.FaceDetection
  alias PhoenixHologramWeb.Hologram.Pages.AdminMoviePage
  alias PhoenixHologramWeb.Hologram.Pages.PlayerPage
  alias PhoenixHologramWeb.Hologram.Pages.PremierePage
  alias PhoenixHologramWeb.Hologram.Pages.ScienceOfFocusPage

  route "/"

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout, banner: :home

  def init(_params, component, _server) do
    movies =
      FaceDetection.list_movies_ordered()
      |> Enum.map(&build_card/1)

    component
    |> put_state(:movies, movies)
    |> put_state(:auth_tab, :login)
  end

  defp build_card(movie) do
    %{
      id: movie.id,
      title: movie.title || movie.path,
      status: movie.status,
      description: movie.description,
      event_line: format_event_line(movie),
      thumbnail_url: "/premiere/videos/#{movie.id}/thumbnail",
      highlight?: highlight_card?(movie)
    }
  end

  defp highlight_card?(movie) do
    title = movie.title || ""
    String.contains?(String.downcase(title), "happy birthday")
  end

  defp format_event_line(movie) do
    case [format_event_date(movie.event_date), movie.location] |> Enum.reject(&is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " | ")
    end
  end

  defp format_event_date(nil), do: nil
  defp format_event_date(date), do: date |> Calendar.strftime("%d %b %Y") |> String.upcase()

  # Pure client-side UI toggle (same idiom as AdminAnalyticsPage's
  # :toggle_filters) — never needs a server round trip. :forgot_password
  # is reached via the login form's "Forgot Password?" link, not a top tab.
  def action(:switch_auth_tab, params, component) do
    tab =
      case params.tab do
        "register" -> :register
        "forgot_password" -> :forgot_password
        _ -> :login
      end

    put_state(component, :auth_tab, tab)
  end

  def template do
    ~HOLO"""
    <div class="min-h-screen">
      <div id="celebrations" class="p-6">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-center justify-center gap-3 mb-1">
            <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
              <path d="M12 2c-6 6-6 20 0 36" />
              <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
            </svg>
            <h2 class="font-display text-xl sm:text-2xl text-center">
              Analyze Our Core Example
            </h2>
            <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
              <path d="M12 2c-6 6-6 20 0 36" />
              <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
            </svg>
          </div>
          <p class="text-center text-sm text-base-content/60 mb-6">
            Every celebration, organized into its own chapter — just like your site will be.
          </p>

          {%if @movies == []}
            <div class="card card-stock shadow-xl">
              <div class="card-body">
                <p class="text-base-content/70">
                  No films yet. Once a video is ingested it will show up here.
                </p>
              </div>
            </div>
          {%else}
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {%for movie <- @movies}
                <div class={
                  if movie.highlight? do
                    "card sm:col-span-2 border-2 border-primary bg-secondary text-secondary-content shadow-xl hover:shadow-2xl transition overflow-hidden"
                  else
                    "card card-stock shadow-xl hover:shadow-2xl transition overflow-hidden"
                  end
                }>
                  <Link to={PlayerPage, id: movie.id}>
                    <figure class="aspect-video bg-base-300">
                      <img src={movie.thumbnail_url} alt={movie.title} class="w-full h-full object-cover" />
                    </figure>
                  </Link>
                  <div class="card-body items-center text-center">
                    <h2 class="card-title font-display">
                      <Link to={PlayerPage, id: movie.id} class="hover:underline">{movie.title}</Link>
                    </h2>
                    {%if movie.description}
                      <p class={
                        if movie.highlight? do
                          "text-sm text-secondary-content/80"
                        else
                          "text-sm text-base-content/70"
                        end
                      }>{movie.description}</p>
                    {/if}
                    {%if movie.event_line}
                      <p class={
                        if movie.highlight? do
                          "text-xs tracking-wide text-secondary-content/70"
                        else
                          "text-xs tracking-wide text-base-content/50"
                        end
                      }>{movie.event_line}</p>
                    {/if}
                    <div class="flex flex-wrap justify-center gap-2 mt-2">
                      <Link to={PlayerPage, id: movie.id} class="btn btn-sm btn-primary">
                        View Video ▶
                      </Link>
                      <Link to={AdminMoviePage, id: movie.id} class="btn btn-sm btn-secondary">
                        Admin View ⚙
                      </Link>
                    </div>
                  </div>
                </div>
              {/for}
            </div>

            <div class="text-center mt-6">
              <Link to={PremierePage} class="link link-hover text-sm">
                See every celebration in the Premiere Hall &rarr;
              </Link>
            </div>
          {/if}
        </div>
      </div>

      <div id="how-it-works" class="border-y border-primary/30 py-8">
        <div class="max-w-3xl mx-auto px-6 grid grid-cols-1 sm:grid-cols-3 gap-6 text-center">
          <div>
            <div class="text-3xl">🔒</div>
            <p class="font-display text-sm mt-2">Secure &amp; Private</p>
          </div>
          <div>
            <div class="text-3xl">🎞️</div>
            <p class="font-display text-sm mt-2">Professional Curation</p>
          </div>
          <div>
            <div class="text-3xl">🔗</div>
            <p class="font-display text-sm mt-2">Custom Shareable Link</p>
          </div>
        </div>
      </div>

      <div id="scientific-importance" class="py-10 px-6">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-center justify-center gap-3 mb-1">
            <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
              <path d="M12 2c-6 6-6 20 0 36" />
              <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
            </svg>
            <h2 class="font-display text-xl sm:text-2xl text-center">
              The Scientific Importance Of Focus
            </h2>
            <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
              <path d="M12 2c-6 6-6 20 0 36" />
              <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
            </svg>
          </div>
          <p class="text-center text-sm text-base-content/60 mb-6">
            Why identifying who matters in every scene makes for a smarter, more resonant film.
          </p>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <div class="flex flex-col items-center sm:flex-row sm:items-start gap-4 text-center sm:text-left">
                <div class="w-12 h-12 shrink-0 rounded-box bg-primary/10 border-2 border-primary/40 flex items-center justify-center">
                  <span class="hero-eye w-6 h-6 text-primary"></span>
                </div>
                <div>
                  <p class="text-sm text-base-content/70">
                    Human visual processing is highly selective — we naturally foveate, directing our sharpest attention toward whichever face or gesture is visually salient, emotionally resonant, or narratively important. In a crowded celebration, knowing who commands that visual prominence is what separates a scene that lands from one that blurs together.
                  </p>
                  <p class="text-sm text-base-content/70 mt-3">
                    Studies show that clearly-focused, prominent subjects lead to clearer emotional communication and stronger recall, while blurry or indistinct scenes create cognitive friction and disengagement. Our Focus Engine — pairing AI scene analysis with real community votes — exists to identify that ground-truth focus, scene by scene, for a truly immersive viewing experience.
                  </p>
                </div>
              </div>
              <div class="text-center mt-4">
                <Link to={ScienceOfFocusPage} class="btn btn-primary btn-sm">See The Full Science &rarr;</Link>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div id="start-your-story" class="p-6">
        <div class="max-w-md mx-auto">
          <h2 class="font-display text-xl sm:text-2xl text-center">Start Your Story</h2>
          <p class="text-sm text-base-content/60 text-center mt-1">
            Sign in to revisit your celebration, or register to begin a new one.
          </p>
          <div class="gold-divider w-16 my-3 mx-auto"></div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <div role="tablist" class="tabs tabs-boxed w-full mb-4 p-1.5 gap-1.5">
                <button
                  type="button"
                  role="tab"
                  $click={:switch_auth_tab, tab: "login"}
                  class={
                    if @auth_tab in [:login, :forgot_password] do
                      "tab flex-1 tab-lg font-display font-semibold bg-primary text-primary-content shadow-md"
                    else
                      "tab flex-1 tab-lg font-display text-base-content/60"
                    end
                  }
                >
                  Log In
                </button>
                <button
                  type="button"
                  role="tab"
                  $click={:switch_auth_tab, tab: "register"}
                  class={
                    if @auth_tab == :register do
                      "tab flex-1 tab-lg font-display font-semibold bg-primary text-primary-content shadow-md"
                    else
                      "tab flex-1 tab-lg font-display text-base-content/60"
                    end
                  }
                >
                  Register
                </button>
              </div>

              {%if @auth_tab == :register}
                <span class="text-xs text-base-content/60 mb-1">Full Name</span>
                <input type="text" placeholder="Your full name" class="input input-bordered w-full" />

                <span class="text-xs text-base-content/60 mb-1 mt-4">Email Address</span>
                <input type="email" placeholder="you@example.com" class="input input-bordered w-full" />

                <span class="text-xs text-base-content/60 mb-1 mt-4">Password</span>
                <input type="password" placeholder="••••••••••" class="input input-bordered w-full" />

                <span class="text-xs text-base-content/60 mb-1 mt-4">Wedding Date</span>
                <input type="date" class="input input-bordered w-full" />

                <span class="btn btn-primary btn-block mt-6 pointer-events-none gap-2">
                  <span class="hero-sparkles w-4 h-4"></span>
                  Register Your Vivah Videos
                </span>
                <p class="text-center text-xs text-base-content/50 mt-2">
                  Account creation is coming soon.
                </p>
              {%else}
                {%if @auth_tab == :forgot_password}
                  <p class="text-sm text-base-content/60 text-center mb-3">
                    Enter your email and we'll send you a link to reset your password.
                  </p>
                  <span class="text-xs text-base-content/60 mb-1">Email address</span>
                  <input type="email" placeholder="you@example.com" class="input input-bordered w-full" />

                  <span class="btn btn-primary btn-block mt-6 pointer-events-none gap-2">
                    <span class="hero-envelope w-4 h-4"></span>
                    Send Reset Link
                  </span>
                  <p class="text-center text-xs text-base-content/50 mt-2">
                    Password recovery is coming soon.
                  </p>

                  <p class="text-center text-sm mt-4">
                    Remembered it?
                    <button
                      type="button"
                      $click={:switch_auth_tab, tab: "login"}
                      class="link link-primary font-semibold"
                    >
                      Back To Log In
                    </button>
                  </p>
                {%else}
                  <span class="text-xs text-base-content/60 mb-1">Email address</span>
                  <input type="email" placeholder="you@example.com" class="input input-bordered w-full" />

                  <div class="flex items-center justify-between mt-4 mb-1">
                    <span class="text-xs text-base-content/60">Password</span>
                    <button
                      type="button"
                      $click={:switch_auth_tab, tab: "forgot_password"}
                      class="text-xs link link-primary"
                    >
                      Forgot Password?
                    </button>
                  </div>
                  <input type="password" placeholder="••••••••••" class="input input-bordered w-full" />

                  <span class="btn btn-primary btn-block mt-6 pointer-events-none gap-2">
                    <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
                    Log In To Your Memories
                  </span>
                  <p class="text-center text-xs text-base-content/50 mt-2">
                    Account sign-in is coming soon.
                  </p>
                {/if}
              {/if}
            </div>
          </div>
        </div>
      </div>

      <div class="bg-secondary text-secondary-content py-8 px-6 text-center">
        <p class="font-display text-lg sm:text-xl italic max-w-xl mx-auto text-balance">
          <span class="text-primary not-italic">&ldquo;</span>Our digital memory timeline is a family treasure!<span class="text-primary not-italic">&rdquo;</span>
        </p>
      </div>
    </div>
    """
  end
end
