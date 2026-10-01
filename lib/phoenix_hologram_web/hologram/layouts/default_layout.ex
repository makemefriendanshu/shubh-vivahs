defmodule PhoenixHologramWeb.Hologram.Layouts.DefaultLayout do
  use Hologram.Component

  alias Hologram.UI.Link
  alias Hologram.UI.Runtime
  alias PhoenixHologram.FaceDetection
  alias PhoenixHologramWeb.Hologram.Pages.AdminAnalyticsPage
  alias PhoenixHologramWeb.Hologram.Pages.AdminMoviePage
  alias PhoenixHologramWeb.Hologram.Pages.DashboardPage
  alias PhoenixHologramWeb.Hologram.Pages.UploadPage
  alias PhoenixHologramWeb.Hologram.Pages.HowItWorksPage
  alias PhoenixHologramWeb.Hologram.Pages.LoginPage
  alias PhoenixHologramWeb.Hologram.Pages.PlayerPage
  alias PhoenixHologramWeb.Hologram.Pages.PremierExperiencePage
  alias PhoenixHologramWeb.Hologram.Pages.PricingPage
  alias PhoenixHologramWeb.Hologram.Pages.PromoRequestsPage
  alias PhoenixHologramWeb.Hologram.Pages.RegisterPage
  alias PhoenixHologramWeb.Hologram.Pages.ScienceOfFocusPage

  # Shared site banner (identity band + gold nav + crossfading photo hero)
  # shown above every Hologram page — lives here, not in each page, so it
  # renders once regardless of which page is wrapped in <slot />. Fixed
  # slide count so the CSS crossfade timeline (see .hero-slide /
  # @keyframes hero-crossfade in app.css) can use static percentages —
  # movies are cycled with rem/2 to fill all 4 slots even if there are
  # fewer than 4 of them.
  @hero_slide_count 4
  @hero_slide_seconds 5

  # :home gets the "Transform Your Wedding Videos..." sales banner (with a
  # CTA button); every other page keeps the original "Welcome to Shubh
  # Vivahas" banner. Set via `layout DefaultLayout, banner: :home` on the page.
  prop :banner, :atom, default: :default

  def init(props, component, server) do
    # Public-only: this hero carousel and nav dropdown are the site's
    # public showcase, shown as-is on every page including Dashboard/
    # UploadPage - a signed-in user's own management view of every movie
    # (public or not) lives in those pages' own "Uploaded Event Videos"
    # cards instead (`FaceDetection.list_movies_ordered/0`).
    movies = FaceDetection.list_public_movies_ordered()

    component =
      component
      |> put_state(:banner, props.banner)
      |> put_state(:asset_version, PhoenixHologramWeb.Layouts.asset_version())
      |> put_state(:hero_images, build_hero_images(movies))
      |> put_state(:themes, PhoenixHologramWeb.DaisyThemes.themes())
      |> put_state(:footer_year, Date.utc_today().year)
      |> put_state(
        :nav_movies,
        Enum.map(movies, fn movie ->
          %{
            id: movie.id,
            title: movie.title || movie.path,
            thumbnail_url: "/premiere/videos/#{movie.id}/thumbnail"
          }
        end)
      )

    {component, server}
  end

  defp build_hero_images([]), do: []

  defp build_hero_images(movies) do
    Enum.map(0..(@hero_slide_count - 1), fn i ->
      movie = Enum.at(movies, rem(i, length(movies)))
      %{url: "/premiere/videos/#{movie.id}/thumbnail", delay_s: i * @hero_slide_seconds}
    end)
  end

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <script>
          {%raw}
          (function () {
            // Applies the chosen daisyUI theme before first paint, and
            // exposes window.phSetTheme so the "Theme" nav dropdown below can
            // change it. Shares the "phx:theme" localStorage key and the
            // data-theme/data-theme-source attributes with root.html.heex, so
            // a theme picked on a Hologram page (e.g. /premiere) also applies
            // on the plain Phoenix "/" page, and vice versa.
            var STORAGE_KEY = 'phx:theme';

            function systemTheme() {
              return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
            }

            function applyTheme(theme) {
              if (theme === 'system') {
                localStorage.removeItem(STORAGE_KEY);
                document.documentElement.setAttribute('data-theme', systemTheme());
                document.documentElement.setAttribute('data-theme-source', 'system');
              } else {
                localStorage.setItem(STORAGE_KEY, theme);
                document.documentElement.setAttribute('data-theme', theme);
                document.documentElement.setAttribute('data-theme-source', 'user');
              }
            }

            window.phSetTheme = applyTheme;
            applyTheme(localStorage.getItem(STORAGE_KEY) || 'system');

            matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () {
              if (document.documentElement.getAttribute('data-theme-source') === 'system') {
                applyTheme('system');
              }
            });

            // Every nav dropdown (Feature Walkthrough, Recognised Faces, Theme)
            // stays open via CSS :focus-within, and clicking any item inside
            // it — a movie <Link>, a plain <a>, or a theme button — focuses
            // that item rather than clearing focus, so the menu never closes
            // on its own. Blur whatever the click landed on, for any dropdown,
            // regardless of whether the click also navigates or SPA-routes.
            document.addEventListener('click', function (e) {
              if (e.target.closest('.dropdown-content')) {
                document.activeElement && document.activeElement.blur();
              }
            });
          })();
          {/raw}
        </script>
        <style>
          {%raw}
          /* Self-contained (no dependency on app.css, which can still be
             loading) styling for the full-page loading overlay built by
             the script below. Colors upgrade automatically to the active
             daisyUI theme once app.css loads, via CSS variable fallbacks. */
          .hologram-loading {
            position: fixed;
            inset: 0;
            z-index: 60;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 1rem;
            background-color: var(--color-base-100, #faf3e8);
            opacity: 0;
            pointer-events: none;
            transition: opacity 0.2s ease;
          }
          .hologram-loading.is-visible {
            opacity: 1;
            pointer-events: auto;
          }
          .hologram-loading.is-hidden {
            display: none;
          }
          .hologram-loading-logo {
            height: 3.5rem;
            width: auto;
          }
          .hologram-loading-spinner {
            width: 2.5rem;
            height: 2.5rem;
            border-radius: 50%;
            border: 3px solid color-mix(in oklch, var(--color-primary, #c9932f) 25%, transparent);
            border-top-color: var(--color-primary, #c9932f);
            animation: hologram-loading-spin 0.8s linear infinite;
          }
          @keyframes hologram-loading-spin {
            to { transform: rotate(360deg); }
          }
          {/raw}
        </style>
        <script>
          {%raw}
          (function () {
            // Shows a full-page spinner once loading is taking a moment
            // (revealed after a short delay so a fast load never flashes
            // it), hidden once the page has fully loaded. Built and torn
            // down entirely in JS, outside <body> — the rest of the page
            // is a Hologram-managed component tree that gets wholly
            // replaced once the client runtime mounts, which would wipe
            // out any classes/state applied to a template-declared node.
            var el = document.createElement('div');
            el.id = 'hologram-loading';
            el.className = 'hologram-loading';
            el.setAttribute('role', 'status');
            el.setAttribute('aria-live', 'polite');
            el.innerHTML =
              '<img src="/images/home-logo.png" alt="Shubh Vivahas" class="hologram-loading-logo" />' +
              '<div class="hologram-loading-spinner"></div>';
            document.documentElement.appendChild(el);

            var revealTimer = setTimeout(function () {
              el.classList.add('is-visible');
            }, 250);

            function hide() {
              clearTimeout(revealTimer);
              el.classList.remove('is-visible');
              el.classList.add('is-hidden');
              setTimeout(function () { el.remove(); }, 250);
            }

            if (document.readyState === 'complete') {
              hide();
            } else {
              window.addEventListener('load', hide);
            }
          })();
          {/raw}
        </script>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Shubh Vivahas</title>
        <link rel="icon" type="image/png" href="/images/home-logo.png" />
        <link rel="alternate icon" href="/favicon.ico" sizes="any" />
        <link rel="stylesheet" href={"/assets/css/app.css?v=#{@asset_version}"} />
        <Runtime />
      </head>
      <body class="wedding-bg min-h-screen flex flex-col">
        <div class="bg-base-100 border-b-[6px] border-double border-primary px-4 sm:px-6 py-4 text-center overflow-x-hidden">
          <a href="/" class="inline-flex flex-nowrap items-center justify-center gap-1 sm:gap-4">
            <img src="/images/brass-lamp.png" class="hidden sm:block sm:h-28 w-auto shrink-0" alt="" aria-hidden="true" />
            <img src="/images/home-logo.png" class="h-20 sm:h-36 w-auto shrink-0" alt="ShubhVivahs.com" />
            <img src="/images/brass-lamp.png" class="hidden sm:block sm:h-28 w-auto shrink-0 scale-x-[-1]" alt="" aria-hidden="true" />
          </a>
          <p class="font-display text-[0.6rem] sm:text-xs tracking-[0.3em] uppercase text-primary font-semibold mt-1">
            Your Digital Wedding Memory Platform
          </p>
        </div>

        <nav class="bg-gradient-to-r from-primary/60 via-primary to-primary/60 text-primary-content">
          <div class="max-w-5xl mx-auto flex flex-wrap justify-center items-center gap-x-3 gap-y-1 py-2 px-4 text-[0.65rem] sm:text-xs font-display tracking-[0.15em] uppercase">
            <a href="/" class="hover:underline shrink-0">Home</a>
            <span class="opacity-50 shrink-0">|</span>
            <div class="dropdown dropdown-hover shrink-0">
              <div tabindex="0" role="button" class="hover:underline cursor-pointer">How It Works ▾</div>
              <ul
                tabindex="0"
                class="dropdown-content menu menu-sm bg-gradient-to-b from-primary to-primary/90 text-primary-content rounded-box z-20 mt-1 w-80 max-w-[calc(100vw-2rem)] p-2 shadow normal-case tracking-normal text-left"
              >
                <li>
                  <Link to={HowItWorksPage} class="flex items-center gap-2 hover:bg-secondary hover:text-primary-content">
                    <span class="hero-book-open w-5 h-5 shrink-0"></span>
                    <span>
                      <span class="block">Your Guide To Celebration</span>
                      <span class="block text-[0.6rem] opacity-70 normal-case tracking-normal">Browsing, admin &amp; scene focus voting</span>
                    </span>
                  </Link>
                </li>
                <li>
                  <Link to={PremierExperiencePage} class="flex items-center gap-2 hover:bg-secondary hover:text-primary-content">
                    <span class="hero-sparkles w-5 h-5 shrink-0"></span>
                    <span>
                      <span class="block">Premier Experience</span>
                      <span class="block text-[0.6rem] opacity-70 normal-case tracking-normal">Streaming, downloads &amp; community</span>
                    </span>
                  </Link>
                </li>
                <li>
                  <Link to={ScienceOfFocusPage} class="flex items-center gap-2 hover:bg-secondary hover:text-primary-content">
                    <span class="hero-beaker w-5 h-5 shrink-0"></span>
                    <span>
                      <span class="block">The Science Of Focus</span>
                      <span class="block text-[0.6rem] opacity-70 normal-case tracking-normal">Why your vote powers the engine</span>
                    </span>
                  </Link>
                </li>
                <li>
                  <Link to={PricingPage} class="flex items-center gap-2 hover:bg-secondary hover:text-primary-content">
                    <span class="hero-currency-rupee w-5 h-5 shrink-0"></span>
                    <span>
                      <span class="block">Pricing</span>
                      <span class="block text-[0.6rem] opacity-70 normal-case tracking-normal">Bands that unlock Admin View</span>
                    </span>
                  </Link>
                </li>
              </ul>
            </div>
            <span class="opacity-50 shrink-0">|</span>
            <a href="/#celebrations" class="hover:underline shrink-0">View Core Example</a>
            <span class="opacity-50 shrink-0">|</span>
            <div class="dropdown dropdown-hover shrink-0">
              <div tabindex="0" role="button" class="hover:underline cursor-pointer">Feature Walkthrough ▾</div>
              <ul
                tabindex="0"
                class="dropdown-content menu menu-sm bg-gradient-to-b from-primary to-primary/90 text-primary-content rounded-box z-20 mt-1 w-64 max-h-80 overflow-y-auto p-2 shadow normal-case tracking-normal text-left"
              >
                <li>
                  <a
                    href="/premiere"
                    class="font-display border-b border-primary-content/30 mb-1 hover:bg-secondary hover:text-primary-content"
                  >
                    All films
                  </a>
                </li>
                {%for movie <- @nav_movies}
                  <li>
                    <Link
                      to={PlayerPage, id: movie.id}
                      class="flex items-center gap-2 hover:bg-secondary hover:text-primary-content"
                    >
                      <img src={movie.thumbnail_url} class="w-10 h-7 object-cover rounded shrink-0" />
                      <span class="truncate">{movie.title}</span>
                    </Link>
                  </li>
                {/for}
              </ul>
            </div>
            <span class="opacity-50 shrink-0">|</span>
            <a href="/#start-your-story" class="hover:underline shrink-0">Create Yours</a>
            <span class="opacity-50 shrink-0">|</span>
            <div class="dropdown dropdown-hover shrink-0">
              <div tabindex="0" role="button" class="hover:underline cursor-pointer">Recognised Faces ▾</div>
              <ul
                tabindex="0"
                class="dropdown-content menu menu-sm bg-gradient-to-b from-primary to-primary/90 text-primary-content rounded-box z-20 mt-1 w-64 max-h-80 overflow-y-auto p-2 shadow normal-case tracking-normal text-left"
              >
                <li>
                  <a
                    href="/admin"
                    class="font-display border-b border-primary-content/30 mb-1 hover:bg-secondary hover:text-primary-content"
                  >
                    All films
                  </a>
                </li>
                {%for movie <- @nav_movies}
                  <li>
                    <Link
                      to={AdminMoviePage, id: movie.id}
                      class="flex items-center gap-2 hover:bg-secondary hover:text-primary-content"
                    >
                      <img src={movie.thumbnail_url} class="w-10 h-7 object-cover rounded shrink-0" />
                      <span class="truncate">{movie.title}</span>
                    </Link>
                  </li>
                {/for}
              </ul>
            </div>
            <span class="opacity-50 shrink-0">|</span>
            <Link to={LoginPage} class="hover:underline shrink-0">Login</Link>
            <span class="opacity-50 shrink-0">|</span>
            <Link to={RegisterPage} class="hover:underline shrink-0">Register</Link>
            <span class="opacity-50 shrink-0">|</span>
            <Link to={DashboardPage} class="hover:underline shrink-0">Dashboard</Link>
            <span class="opacity-50 shrink-0">|</span>
            <Link to={UploadPage} class="hover:underline shrink-0">Manage Videos</Link>
            <span class="opacity-50 shrink-0">|</span>
            <Link to={AdminAnalyticsPage} class="hover:underline shrink-0">Admin Analytics</Link>
            <span class="opacity-50 shrink-0">|</span>
            <Link to={PromoRequestsPage} class="hover:underline shrink-0">Promo Requests</Link>
            <span class="opacity-50 shrink-0">|</span>
            <div class="dropdown dropdown-hover dropdown-end shrink-0">
              <div tabindex="0" role="button" class="hover:underline cursor-pointer">Theme ▾</div>
              <ul
                tabindex="0"
                class="dropdown-content menu menu-sm bg-gradient-to-b from-primary to-primary/90 text-primary-content rounded-box z-20 mt-1 w-48 max-h-80 overflow-y-auto p-2 shadow normal-case tracking-normal text-left"
              >
                <li>
                  <a
                    onclick="phSetTheme('system')"
                    class="cursor-pointer hover:bg-secondary hover:text-primary-content"
                  >
                    System
                  </a>
                </li>
                {%for theme <- @themes}
                  <li>
                    <a
                      onclick={"phSetTheme('#{theme}')"}
                      class="capitalize cursor-pointer hover:bg-secondary hover:text-primary-content"
                    >
                      {theme}
                    </a>
                  </li>
                {/for}
              </ul>
            </div>
          </div>
        </nav>

        <div class={
          if @banner == :home do
            "relative min-h-64 sm:min-h-80 border-b-4 border-primary overflow-hidden"
          else
            "relative h-64 sm:h-80 border-b-4 border-primary overflow-hidden"
          end
        }>
          {%if @hero_images == []}
            <div class="absolute inset-0 wedding-bg"></div>
          {%else}
            {%for slide <- @hero_images}
              <img src={slide.url} style={"animation-delay: #{slide.delay_s}s"} class="hero-slide" />
            {/for}
          {/if}
          <div class="absolute inset-0 bg-gradient-to-t from-secondary/85 via-secondary/15 to-transparent"></div>

          {%if @banner == :home}
            <div class="relative px-6 py-8 sm:py-14 text-center">
              <div class="inline-block border border-primary/80 px-6 py-4 sm:px-14 sm:py-6">
                <p class="font-display text-primary-content text-base sm:text-2xl font-semibold tracking-wide text-balance">
                  Transform Your Wedding Videos Into A Digital Keepsake.
                </p>
                <p class="font-display text-primary-content/90 text-xs sm:text-lg mt-2 text-balance">
                  Ready to share your Shubh Vivahas videos?
                </p>
                <a href="/#celebrations" class="btn btn-primary btn-sm sm:btn-md mt-4">Get Service Like This</a>
              </div>
            </div>
          {%else}
            {%if @banner == :pricing}
              <div class="relative px-6 py-8 sm:py-14 text-center">
                <div class="inline-block border border-primary/80 px-6 py-4 sm:px-14 sm:py-6">
                  <p class="font-display text-primary-content text-base sm:text-2xl font-semibold tracking-wide text-balance">
                    Unlock Premium Admin Facilities
                  </p>
                  <p class="font-display text-primary-content/90 text-xs sm:text-lg mt-2 text-balance">
                    Pricing bands for every celebration
                  </p>
                  <a href="#bands" class="btn btn-primary btn-sm sm:btn-md mt-4">View Pricing Bands</a>
                </div>
              </div>
            {%else}
            <div class="absolute inset-x-0 bottom-0 px-6 pb-6 sm:pb-10 text-center">
              <div class="inline-block border border-primary/80 px-6 py-4 sm:px-14 sm:py-6">
                <p class="font-display text-primary-content text-base sm:text-2xl tracking-wide">
                  Welcome to Shubh Vivahas —
                </p>
                <p class="font-display text-primary-content/90 text-sm sm:text-xl mt-1">
                  Where Love Begins &amp; Tradition Flourishes
                </p>
              </div>
            </div>
            {/if}
          {/if}
        </div>

        <main id="page-content" class="flex-1">
          <slot />
        </main>
        <footer class="bg-secondary text-secondary-content">
          <div class="max-w-5xl mx-auto px-6 py-8 grid grid-cols-1 sm:grid-cols-3 gap-6 items-center text-center sm:text-left">
            <div class="flex flex-col gap-2 items-center sm:items-start">
              <a
                href="https://wa.me/919880538028"
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center gap-2 hover:text-primary"
              >
                <span class="hero-phone size-4 shrink-0"></span>
                <span class="text-sm">+91 98805 38028</span>
              </a>
            </div>

            <div class="flex flex-col items-center gap-2">
              <span class="font-display text-xs tracking-[0.25em] uppercase text-primary">Social Media</span>
              <div class="flex items-center gap-3">
                <a
                  href="https://www.instagram.com/ianshuman75"
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label="Instagram"
                  class="w-8 h-8 rounded-full border border-primary/60 flex items-center justify-center hover:bg-primary hover:text-secondary transition"
                >
                  <svg viewBox="0 0 24 24" class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.6">
                    <rect x="3.5" y="3.5" width="17" height="17" rx="4.5" />
                    <circle cx="12" cy="12" r="3.6" />
                    <circle cx="17" cy="7" r="0.9" fill="currentColor" stroke="none" />
                  </svg>
                </a>
                <a
                  href="https://www.youtube.com/@anshuman4527"
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label="YouTube"
                  class="w-8 h-8 rounded-full border border-primary/60 flex items-center justify-center hover:bg-primary hover:text-secondary transition"
                >
                  <svg viewBox="0 0 24 24" class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.6">
                    <rect x="3" y="6" width="18" height="12" rx="3" />
                    <path d="M10.5 9.5l4.5 2.5-4.5 2.5z" fill="currentColor" stroke="none" />
                  </svg>
                </a>
                <a
                  href="https://github.com/makemefriendanshu/phoenix-hologram"
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label="GitHub"
                  class="w-8 h-8 rounded-full border border-primary/60 flex items-center justify-center hover:bg-primary hover:text-secondary transition"
                >
                  <svg viewBox="0 0 24 24" class="w-4 h-4" fill="currentColor" stroke="none">
                    <path d="M12 2.2c-5.5 0-10 4.5-10 10 0 4.4 2.9 8.2 6.8 9.5.5.1.7-.2.7-.5v-1.8c-2.8.6-3.4-1.2-3.4-1.2-.4-1.1-1.1-1.4-1.1-1.4-.9-.6.1-.6.1-.6 1 .1 1.5 1 1.5 1 .9 1.5 2.3 1.1 2.9.8.1-.7.4-1.1.6-1.4-2.2-.3-4.6-1.1-4.6-4.9 0-1.1.4-2 1-2.6-.1-.3-.4-1.3.1-2.6 0 0 .8-.3 2.7 1a9.4 9.4 0 0 1 5 0c1.9-1.3 2.7-1 2.7-1 .5 1.3.2 2.3.1 2.6.6.6 1 1.5 1 2.6 0 3.8-2.4 4.6-4.6 4.9.4.3.7.9.7 1.9v2.8c0 .3.2.6.7.5 3.9-1.3 6.8-5.1 6.8-9.5 0-5.5-4.5-10-10-10z" />
                  </svg>
                </a>
              </div>
            </div>

            <div class="flex justify-center sm:justify-end">
              <a href="/#start-your-story" class="btn btn-primary btn-sm">Register</a>
            </div>
          </div>

          <div class="border-t border-primary/20 py-3 text-center text-xs tracking-wide text-secondary-content/70">
            &copy; {@footer_year} Shubh Vivahas. All rights reserved.
          </div>
        </footer>

        <script>
          {%raw}
          (function () {
            // The identity band, nav, and hero banner above #page-content
            // are identical on every page, so landing at the very top just
            // re-shows the same header on each navigation. The Hologram
            // client runtime forces window.scrollTo(0, 0) on every SPA
            // navigation (loadNewPage, right before history.pushState) -
            // wrapping pushState runs this right after that reset, in the
            // same synchronous tick, so it overrides the jump-to-top with a
            // landing just past the banner instead. Also covers a real full
            // page load or refresh, and browser back/forward (popstate).
            // Stops a bit short of aligning #page-content flush with the
            // viewport top, so the landing scroll distance is a little
            // shorter and the very bottom of the hero stays peeking in.
            var shortfallPx = 120;

            function scrollPastBanner() {
              var el = document.getElementById('page-content');
              if (!el) { return; }
              var targetY = el.getBoundingClientRect().top + window.scrollY - shortfallPx;
              window.scrollTo(0, Math.max(0, targetY));
            }

            scrollPastBanner();

            var originalPushState = history.pushState;
            history.pushState = function () {
              originalPushState.apply(history, arguments);
              scrollPastBanner();
            };

            window.addEventListener('popstate', scrollPastBanner);
          })();
          {/raw}
        </script>
      </body>
    </html>
    """
  end
end
