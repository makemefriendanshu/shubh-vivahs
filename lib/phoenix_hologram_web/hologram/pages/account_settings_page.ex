defmodule PhoenixHologramWeb.Hologram.Pages.AccountSettingsPage do
  @moduledoc """
  Real account settings, gated behind `RequireAuthenticatedUser` like
  DashboardPage. Three independent, real pieces, all backed by
  `PhoenixHologram.Accounts`: editing the profile — name, email, phone,
  wedding date (`Accounts.update_profile/2`) — changing password
  (`Accounts.update_password/3`, which re-verifies the current password
  server-side before accepting a new one), and uploading a profile
  photo. Unlike EditEventDetailsPage and friends, these are fully wired
  up, not sample/disabled inputs.

  The photo upload is NOT a Hologram command — Hologram's action/command
  protocol carries JSON-ish term data, not binary file contents, and
  has no `<input type="file">` support (confirmed: no such mechanism
  exists anywhere in the `hologram` dependency). It's a plain HTML
  `<form method="post" enctype="multipart/form-data">` targeting
  `PhoenixHologramWeb.AccountAvatarController`, submitted via
  `action(:upload_avatar_clicked, ...)` calling `JS.exec` to copy
  `window.Hologram.csrfToken` (set by Hologram's own runtime bootstrap
  script on every page load) into a hidden field before calling
  `form.submit()` — see that controller's moduledoc for why the token
  has to be validated manually there instead of via Phoenix's own
  `:protect_from_forgery`. The upload causes a real full-page POST/
  redirect back here (not a Hologram SPA transition); a failure is
  passed back via the `"avatar_error"` session key rather than a query
  param — Hologram only reads query-string page params on a
  client-side SPA navigation (`handle_subsequent_page_request/2`), a
  genuine HTTP redirect always takes the initial-page-request path,
  which builds `params` from the URL's path segments only (see
  `Hologram.Controller.handle_initial_page_request/2`) and would
  silently ignore a query string here. `init/3` reads the session key
  once and clears it, so it behaves like a one-shot flash.

  `wedding_date` is stored as `Ecto.Date` but HTML date inputs and
  Hologram's client-side JS both work in ISO-8601 strings, so it's
  converted both ways at the state boundary (`date_to_string/1` in,
  `blank_to_nil/1` back out).

  An "Account Tier" card shows the same real superuser/premium state as
  DashboardPage's Account Settings summary (`Accounts.superuser?/1`,
  `Accounts.premium?/1`) — a "Superuser" badge and "All Features
  Unlocked" for a superuser, otherwise a "Free" badge and a link to
  UpgradePage (the actual /upgrade "buy" page) to unlock Premium.

  The four cards sit in two `grid grid-cols-1 sm:grid-cols-2` rows
  (Photo + Account Tier, then Profile + Change Password) rather than
  one long single-column stack — two per row from `sm:` up, one per
  row (full width) below that, matching the responsive grid pattern
  DashboardPage already uses for its own card pairs.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias PhoenixHologram.Accounts
  alias PhoenixHologramWeb.Hologram.Middleware.RequireAuthenticatedUser
  alias PhoenixHologramWeb.Hologram.Pages.DashboardPage
  alias PhoenixHologramWeb.Hologram.Pages.UpgradePage

  route "/account-settings"

  middleware RequireAuthenticatedUser

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server) do
    user = get_stash(server, :current_user)
    avatar_error = get_session(server, "avatar_error")
    server = delete_session(server, "avatar_error")

    component =
      component
      |> put_state(:name, user.name)
      |> put_state(:email, user.email)
      |> put_state(:phone, user.phone || "")
      |> put_state(:avatar_url, user.avatar_url)
      |> put_state(:avatar_error, avatar_error)
      |> put_state(:wedding_date, date_to_string(user.wedding_date))
      |> put_state(:superuser?, Accounts.superuser?(user))
      |> put_state(:premium?, Accounts.premium?(user))
      |> put_state(:profile_error, nil)
      |> put_state(:profile_success?, false)
      |> put_state(:profile_submitting?, false)
      |> put_state(:current_password, "")
      |> put_state(:new_password, "")
      |> put_state(:confirm_password, "")
      |> put_state(:password_error, nil)
      |> put_state(:password_success?, false)
      |> put_state(:password_submitting?, false)

    {component, server}
  end

  def action(:update_name, params, component) do
    put_state(component, name: params.event.value, profile_error: nil, profile_success?: false)
  end

  def action(:update_email, params, component) do
    put_state(component, email: params.event.value, profile_error: nil, profile_success?: false)
  end

  def action(:update_phone, params, component) do
    put_state(component, phone: params.event.value, profile_error: nil, profile_success?: false)
  end

  def action(:update_wedding_date, params, component) do
    put_state(component, wedding_date: params.event.value, profile_error: nil, profile_success?: false)
  end

  def action(:save_profile_clicked, _params, component) do
    name = String.trim(component.state.name)
    email = String.trim(component.state.email)

    if name == "" or email == "" do
      put_state(component, profile_error: "Please fill in both your name and email.", profile_success?: false)
    else
      component
      |> put_state(profile_submitting?: true, profile_error: nil, profile_success?: false)
      |> put_command(:update_profile,
        name: name,
        email: email,
        phone: blank_to_nil(component.state.phone),
        wedding_date: blank_to_nil(component.state.wedding_date)
      )
    end
  end

  def action(:profile_updated, params, component) do
    component
    |> put_state(:name, params.name)
    |> put_state(:email, params.email)
    |> put_state(:phone, params.phone || "")
    |> put_state(:wedding_date, params.wedding_date || "")
    |> put_state(:profile_submitting?, false)
    |> put_state(:profile_success?, true)
  end

  # No server round trip — just copies the CSRF token Hologram's own
  # runtime already set on `window.Hologram` (see this module's doc)
  # into the upload form's hidden field, then submits it as a real
  # multipart POST/full-page navigation, not a Hologram command.
  def action(:upload_avatar_clicked, _params, component) do
    JS.exec("""
    const tokenInput = document.getElementById('avatar-csrf-token');
    if (tokenInput) { tokenInput.value = window.Hologram.csrfToken; }
    const form = document.getElementById('avatar-upload-form');
    if (form) { form.submit(); }
    """)

    component
  end

  def action(:profile_update_failed, params, component) do
    put_state(component, profile_submitting?: false, profile_error: params.message, profile_success?: false)
  end

  def action(:update_current_password, params, component) do
    put_state(component, current_password: params.event.value, password_error: nil, password_success?: false)
  end

  def action(:update_new_password, params, component) do
    put_state(component, new_password: params.event.value, password_error: nil, password_success?: false)
  end

  def action(:update_confirm_password, params, component) do
    put_state(component, confirm_password: params.event.value, password_error: nil, password_success?: false)
  end

  def action(:change_password_clicked, _params, component) do
    current_password = component.state.current_password
    new_password = component.state.new_password
    confirm_password = component.state.confirm_password

    cond do
      current_password == "" or new_password == "" or confirm_password == "" ->
        put_state(component, password_error: "Please fill in all three password fields.", password_success?: false)

      String.length(new_password) < 8 ->
        put_state(component, password_error: "New password must be at least 8 characters.", password_success?: false)

      new_password != confirm_password ->
        put_state(component, password_error: "New password and confirmation don't match.", password_success?: false)

      true ->
        component
        |> put_state(password_submitting?: true, password_error: nil, password_success?: false)
        |> put_command(:update_password, current_password: current_password, new_password: new_password)
    end
  end

  def action(:password_updated, _params, component) do
    component
    |> put_state(:current_password, "")
    |> put_state(:new_password, "")
    |> put_state(:confirm_password, "")
    |> put_state(:password_submitting?, false)
    |> put_state(:password_success?, true)
  end

  def action(:password_update_failed, params, component) do
    put_state(component, password_submitting?: false, password_error: params.message, password_success?: false)
  end

  def command(:update_profile, params, server) do
    user = get_stash(server, :current_user)

    case Accounts.update_profile(user, params) do
      {:ok, updated_user} ->
        put_action(server, :profile_updated,
          name: updated_user.name,
          email: updated_user.email,
          phone: updated_user.phone,
          wedding_date: date_to_string(updated_user.wedding_date)
        )

      {:error, changeset} ->
        put_action(server, :profile_update_failed, message: profile_error_message(changeset))
    end
  end

  def command(:update_password, %{current_password: current_password, new_password: new_password}, server) do
    user = get_stash(server, :current_user)

    case Accounts.update_password(user, current_password, new_password) do
      {:ok, _updated_user} ->
        put_action(server, :password_updated)

      {:error, :invalid_current_password} ->
        put_action(server, :password_update_failed, message: "Current password is incorrect.")

      {:error, _changeset} ->
        put_action(server, :password_update_failed, message: "Please check your new password and try again.")
    end
  end

  defp profile_error_message(changeset) do
    if Keyword.has_key?(changeset.errors, :email) do
      "That email is already in use by another account."
    else
      "Please check your details and try again."
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp date_to_string(nil), do: ""
  defp date_to_string(%Date{} = date), do: Date.to_iso8601(date)

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <div class="max-w-3xl mx-auto">
        <div class="flex items-center justify-center gap-3 mb-1">
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
          <h1 class="font-display text-xl sm:text-2xl text-center">
            Account Settings
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-xs text-base-content/50 mb-2">
          <Link to={DashboardPage} class="link link-hover">Dashboard</Link>
          &gt; <span class="text-base-content/70">Account Settings</span>
        </p>
        <div class="gold-divider w-24 mx-auto mb-6"></div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
          <div class="card card-stock shadow-xl">
            <div class="card-body items-center text-center">
              <h2 class="font-display text-base uppercase tracking-wide self-start">Profile Photo</h2>

              {%if @avatar_url}
                <img src={@avatar_url} alt="Profile photo" class="w-24 h-24 rounded-full object-cover border-2 border-primary/40 mt-2" />
              {%else}
                <div class="w-24 h-24 rounded-full bg-base-300 border-2 border-primary/20 flex items-center justify-center mt-2">
                  <span class="hero-user w-10 h-10 text-base-content/40"></span>
                </div>
              {/if}

              <form id="avatar-upload-form" method="post" action="/account/avatar" enctype="multipart/form-data" class="mt-4 w-full flex flex-col items-center gap-3">
                <input type="hidden" id="avatar-csrf-token" name="_csrf_token" value="" />
                <input type="file" name="avatar" accept="image/*" class="file-input file-input-bordered file-input-sm w-full max-w-xs" />

                {%if @avatar_error}
                  <p class="text-xs text-error">{@avatar_error}</p>
                {/if}

                <button type="button" $click="upload_avatar_clicked" class="btn btn-secondary btn-sm gap-2">
                  <span class="hero-arrow-up-tray w-4 h-4"></span>
                  Upload Photo
                </button>
              </form>
              <p class="text-xs text-base-content/50 mt-1">JPG, PNG, GIF, or WEBP, up to 5MB.</p>
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">Account Tier</h2>

              {%if @superuser?}
                <div class="flex items-center gap-2 mt-2">
                  <span class="badge badge-secondary gap-1">
                    <span class="hero-shield-check w-3.5 h-3.5"></span>
                    Superuser
                  </span>
                </div>
                <p class="text-sm text-base-content/70 mt-2">
                  Access Tier: All Features Unlocked (Superuser)
                </p>
              {%else}
                <div class="flex items-center gap-2 mt-2">
                  {%if @premium?}
                    <span class="badge badge-success gap-1">
                      <span class="hero-check-badge w-3.5 h-3.5"></span>
                      Premium
                    </span>
                  {%else}
                    <span class="badge badge-outline gap-1">Free</span>
                  {/if}
                </div>
                <p class="text-sm text-base-content/70 mt-2">
                  {%if @premium?}
                    You have Premium access unlocked.
                  {%else}
                    Upgrade to unlock Admin View and more.
                  {/if}
                </p>
                {%if !@premium?}
                  <div class="mt-4">
                    <Link to={UpgradePage} class="btn btn-primary btn-sm gap-2">
                      <span class="hero-lock-open w-4 h-4"></span>
                      Upgrade To Premium
                    </Link>
                  </div>
                {/if}
              {/if}
            </div>
          </div>
        </div>

        <div class="mt-6 grid grid-cols-1 sm:grid-cols-2 gap-6">
          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">Profile</h2>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Full Name</label>
                <input
                  type="text"
                  value={@name}
                  $change="update_name"
                  class="input input-bordered input-sm w-full mt-1"
                />
              </div>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Email Address</label>
                <input
                  type="email"
                  value={@email}
                  $change="update_email"
                  class="input input-bordered input-sm w-full mt-1"
                />
              </div>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Phone Number</label>
                <input
                  type="tel"
                  placeholder="Your phone number"
                  value={@phone}
                  $change="update_phone"
                  class="input input-bordered input-sm w-full mt-1"
                />
              </div>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Wedding Date</label>
                <input
                  type="date"
                  value={@wedding_date}
                  $change="update_wedding_date"
                  class="input input-bordered input-sm w-full mt-1"
                />
              </div>

              {%if @profile_error}
                <p class="text-xs text-error mt-2">{@profile_error}</p>
              {/if}
              {%if @profile_success?}
                <p class="text-xs text-success mt-2">Profile updated.</p>
              {/if}

              <button
                type="button"
                $click="save_profile_clicked"
                disabled={@profile_submitting?}
                class="btn btn-primary btn-block gap-2 mt-4"
              >
                {%if @profile_submitting?}
                  <span class="loading loading-spinner loading-xs"></span>
                  Saving...
                {%else}
                  <span class="hero-check-circle w-4 h-4"></span>
                  Save Profile
                {/if}
              </button>
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">Change Password</h2>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Current Password</label>
                <input
                  type="password"
                  value={@current_password}
                  $change="update_current_password"
                  class="input input-bordered input-sm w-full mt-1"
                />
              </div>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">New Password</label>
                <input
                  type="password"
                  placeholder="At least 8 characters"
                  value={@new_password}
                  $change="update_new_password"
                  class="input input-bordered input-sm w-full mt-1"
                />
              </div>

              <div class="mt-4">
                <label class="text-xs uppercase tracking-wide text-base-content/50">Confirm New Password</label>
                <input
                  type="password"
                  value={@confirm_password}
                  $change="update_confirm_password"
                  $key_down.enter="change_password_clicked"
                  class="input input-bordered input-sm w-full mt-1"
                />
              </div>

              {%if @password_error}
                <p class="text-xs text-error mt-2">{@password_error}</p>
              {/if}
              {%if @password_success?}
                <p class="text-xs text-success mt-2">Password changed.</p>
              {/if}

              <button
                type="button"
                $click="change_password_clicked"
                disabled={@password_submitting?}
                class="btn btn-primary btn-block gap-2 mt-4"
              >
                {%if @password_submitting?}
                  <span class="loading loading-spinner loading-xs"></span>
                  Changing...
                {%else}
                  <span class="hero-key w-4 h-4"></span>
                  Change Password
                {/if}
              </button>
            </div>
          </div>
        </div>

        <div class="flex flex-col items-center gap-3 mt-6">
          <Link to={DashboardPage} class="btn btn-outline btn-block gap-2">
            <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
            Back To Dashboard
          </Link>
        </div>

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
