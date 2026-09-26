defmodule PhoenixHologramWeb.Hologram.Pages.ForgotPasswordPage do
  @moduledoc """
  Visual-only password recovery page, mirrors LoginPage / RegisterPage:
  there is no user/account system in the app yet (no schema, password
  hashing, or session-based auth), so the form here does not send any
  reset email. Reached from LoginPage's "Forgot Password?" link.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias PhoenixHologramWeb.Hologram.Pages.LoginPage

  route "/forgot-password"

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
            Recover Your Access
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-6">
          Enter your email and we'll send you a link to reset your password.
        </p>

        <div class="card card-stock shadow-xl">
          <div class="card-body">
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
              <Link to={LoginPage} class="link link-primary font-semibold">Back To Log In</Link>
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
