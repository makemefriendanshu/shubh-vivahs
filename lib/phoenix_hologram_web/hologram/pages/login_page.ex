defmodule PhoenixHologramWeb.Hologram.Pages.LoginPage do
  @moduledoc """
  Visual login page only — there is no user/account system in the app yet
  (no schema, password hashing, or session-based auth), so the form here
  does not authenticate anyone. It exists to match the design mockup and
  link to RegisterPage until a real auth system is built.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias PhoenixHologramWeb.Hologram.Pages.ForgotPasswordPage
  alias PhoenixHologramWeb.Hologram.Pages.RegisterPage

  route "/login"

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6 flex items-start justify-center">
      <div class="w-full max-w-md">
        <div class="flex items-center justify-center gap-3 mb-1">
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
          <h1 class="font-display text-xl sm:text-2xl text-center">
            Access Your Eternal Keepsake
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-6">
          Sign in to revisit the celebrations you've been entrusted with.
        </p>

        <div class="card card-stock shadow-xl">
          <div class="card-body">
            <span class="text-xs text-base-content/60 mb-1">Email address</span>
            <input type="email" placeholder="you@example.com" class="input input-bordered w-full" />

            <div class="flex items-center justify-between mt-4 mb-1">
              <span class="text-xs text-base-content/60">Password</span>
              <Link to={ForgotPasswordPage} class="text-xs link link-primary">Forgot Password?</Link>
            </div>
            <input type="password" placeholder="••••••••••" class="input input-bordered w-full" />

            <span class="btn btn-primary btn-block mt-6 pointer-events-none gap-2">
              <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
              Log In To Your Memories
            </span>
            <p class="text-center text-xs text-base-content/50 mt-2">
              Account sign-in is coming soon.
            </p>

            <p class="text-center text-sm mt-4">
              First time here?
              <Link to={RegisterPage} class="link link-primary font-semibold">Create Your Story</Link>
            </p>
          </div>
        </div>

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
