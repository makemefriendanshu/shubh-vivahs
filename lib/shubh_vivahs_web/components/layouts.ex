defmodule ShubhVivahsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ShubhVivahsWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/home-logo.png"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_picker />
          </li>
          <li>
            <a href="https://phoenix.hexdocs.pm/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Mtime (as a unix timestamp) of the compiled `app.css`, used as a cache-
  busting query param on its `<link>` tag in root.html.heex. Without this,
  Cloudflare (and browsers) key their cache on the bare `/assets/css/app.css`
  URL, which never changes between deploys — real users kept getting a
  stale stylesheet minutes after a CSS change actually shipped, since
  nothing told the CDN edge to treat it as a new resource. Reads the file's
  timestamp on every render rather than baking in a build-time constant, so
  it stays correct across `mix phx.server` restarts without a real release
  pipeline's asset-digest step.
  """
  def asset_version do
    Application.app_dir(:shubh_vivahs, "priv/static/assets/css/app.css")
    |> File.stat!()
    |> Map.fetch!(:mtime)
    |> NaiveDateTime.from_erl!()
    |> NaiveDateTime.diff(~N[1970-01-01 00:00:00])
  end

  @doc """
  Dropdown listing every daisyUI theme enabled in app.css (plus "System",
  which follows the OS light/dark preference), so any theme can be picked
  from any page.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_picker(assigns) do
    assigns = assign(assigns, :themes, ShubhVivahsWeb.DaisyThemes.themes())

    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-sm btn-ghost gap-1">
        <.icon name="hero-swatch-micro" class="size-4 opacity-75" />
        <span class="hidden sm:inline">Theme</span>
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu menu-sm bg-base-200 text-base-content rounded-box z-30 mt-2 w-48 max-h-80 overflow-y-auto p-2 shadow"
      >
        <li>
          <button type="button" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="system">
            System
          </button>
        </li>
        <li :for={theme <- @themes}>
          <button
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme={theme}
            class="capitalize"
          >
            {theme}
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
