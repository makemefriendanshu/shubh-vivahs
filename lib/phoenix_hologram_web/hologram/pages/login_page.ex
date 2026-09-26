defmodule PhoenixHologramWeb.Hologram.Pages.LoginPage do
  @moduledoc """
  Real sign-in: submits email/password to `command(:log_in, ...)`, which
  authenticates against `PhoenixHologram.Accounts` and, on success, calls
  `put_user_id/2` — Hologram's session-backed login mechanism — before
  navigating to DashboardPage. `RegisterPage` is the counterpart for
  creating a new account.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias PhoenixHologram.Accounts
  alias PhoenixHologramWeb.Hologram.Pages.ForgotPasswordPage
  alias PhoenixHologramWeb.Hologram.Pages.RegisterPage

  route "/login"

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:email, "")
    |> put_state(:password, "")
    |> put_state(:error, nil)
    |> put_state(:submitting?, false)
  end

  def action(:update_email, params, component) do
    put_state(component, email: params.event.value, error: nil)
  end

  def action(:update_password, params, component) do
    put_state(component, password: params.event.value, error: nil)
  end

  def action(:submit_clicked, _params, component) do
    email = String.trim(component.state.email)
    password = component.state.password

    cond do
      email == "" or password == "" ->
        put_state(component, :error, "Please enter both your email and password.")

      true ->
        component
        |> put_state(submitting?: true, error: nil)
        |> put_command(:log_in, email: email, password: password)
    end
  end

  # A real browser navigation, not put_page/Link — Hologram's client-side
  # SPA transition around an identity change (login/register/logout) has a
  # timing-sensitive double-render that only surfaces under real network
  # latency (reproduced on production, not localhost), so every
  # identity-changing transition in this app forces a full page load
  # instead (see DashboardPage's :logged_out and RegisterPage's
  # :register_succeeded for the same fix).
  def action(:login_succeeded, _params, component) do
    JS.exec("window.location.href = '/dashboard';")
    component
  end

  def action(:login_failed, params, component) do
    put_state(component, submitting?: false, error: params.message)
  end

  def command(:log_in, %{email: email, password: password}, server) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        server
        |> put_user_id(user.id)
        |> put_action(:login_succeeded)

      {:error, :invalid_credentials} ->
        put_action(server, :login_failed, message: "Invalid email or password.")
    end
  end

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
            <input
              type="email"
              placeholder="you@example.com"
              value={@email}
              $change="update_email"
              class="input input-bordered w-full"
            />

            <div class="flex items-center justify-between mt-4 mb-1">
              <span class="text-xs text-base-content/60">Password</span>
              <Link to={ForgotPasswordPage} class="text-xs link link-primary">Forgot Password?</Link>
            </div>
            <input
              type="password"
              placeholder="••••••••••"
              value={@password}
              $change="update_password"
              $key_down.enter="submit_clicked"
              class="input input-bordered w-full"
            />

            {%if @error}
              <p class="text-xs text-error mt-2">{@error}</p>
            {/if}

            <button
              type="button"
              $click="submit_clicked"
              disabled={@submitting?}
              class="btn btn-primary btn-block mt-6 gap-2"
            >
              {%if @submitting?}
                <span class="loading loading-spinner loading-xs"></span>
                Signing In...
              {%else}
                <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
                Log In To Your Memories
              {/if}
            </button>

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
