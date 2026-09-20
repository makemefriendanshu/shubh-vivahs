defmodule PhoenixHologramWeb.Hologram.Pages.RegisterPage do
  @moduledoc """
  Real account creation: submits name/email/password to
  `command(:register, ...)`, which creates a `PhoenixHologram.Accounts.User`
  (never superuser — see `Accounts.register_user/1`) and, on success, logs
  the new account in via `put_user_id/2` before navigating to
  DashboardPage. `LoginPage` is the counterpart for an existing account.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias PhoenixHologram.Accounts
  alias PhoenixHologramWeb.Hologram.Pages.LoginPage

  route "/register"

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:name, "")
    |> put_state(:email, "")
    |> put_state(:password, "")
    |> put_state(:error, nil)
    |> put_state(:submitting?, false)
  end

  def action(:update_name, params, component) do
    put_state(component, name: params.event.value, error: nil)
  end

  def action(:update_email, params, component) do
    put_state(component, email: params.event.value, error: nil)
  end

  def action(:update_password, params, component) do
    put_state(component, password: params.event.value, error: nil)
  end

  def action(:submit_clicked, _params, component) do
    name = String.trim(component.state.name)
    email = String.trim(component.state.email)
    password = component.state.password

    cond do
      name == "" or email == "" or password == "" ->
        put_state(component, :error, "Please fill in your name, email, and password.")

      String.length(password) < 8 ->
        put_state(component, :error, "Password must be at least 8 characters.")

      true ->
        component
        |> put_state(submitting?: true, error: nil)
        |> put_command(:register, name: name, email: email, password: password)
    end
  end

  # Real browser navigation, not put_page — see LoginPage's :login_succeeded
  # for why every identity-changing transition in this app uses a full
  # page load instead of Hologram's client-side SPA navigation.
  def action(:register_succeeded, _params, component) do
    JS.exec("window.location.href = '/dashboard';")
    component
  end

  def action(:register_failed, params, component) do
    put_state(component, submitting?: false, error: params.message)
  end

  def command(:register, %{name: name, email: email, password: password}, server) do
    case Accounts.register_user(%{name: name, email: email, password: password}) do
      {:ok, user} ->
        server
        |> put_user_id(user.id)
        |> put_action(:register_succeeded)

      {:error, changeset} ->
        put_action(server, :register_failed, message: error_message(changeset))
    end
  end

  defp error_message(changeset) do
    if Keyword.has_key?(changeset.errors, :email) do
      "That email is already registered — try logging in instead."
    else
      "Please check your details and try again."
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
            Create Your Eternal Story
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-6">
          A few details, and we'll start curating your celebration.
        </p>

        <div class="card card-stock shadow-xl">
          <div class="card-body">
            <span class="text-xs text-base-content/60 mb-1">Full Name</span>
            <input
              type="text"
              placeholder="Your full name"
              value={@name}
              $change="update_name"
              class="input input-bordered w-full"
            />

            <span class="text-xs text-base-content/60 mb-1 mt-4">Email Address</span>
            <input
              type="email"
              placeholder="you@example.com"
              value={@email}
              $change="update_email"
              class="input input-bordered w-full"
            />

            <span class="text-xs text-base-content/60 mb-1 mt-4">Password</span>
            <input
              type="password"
              placeholder="At least 8 characters"
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
                Creating Your Story...
              {%else}
                <span class="hero-sparkles w-4 h-4"></span>
                Register Your Vivah Videos
              {/if}
            </button>

            <p class="text-center text-sm mt-4">
              Already have an account?
              <Link to={LoginPage} class="link link-primary font-semibold">Log In Here</Link>
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
