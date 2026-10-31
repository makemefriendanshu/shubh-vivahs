defmodule ShubhVivahsWeb.Hologram.Pages.CounterPage do
  use Hologram.Page

  route "/hologram"

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :count, 0)
  end

  def template do
    ~HOLO"""
    <div class="min-h-screen flex items-center justify-center p-6">
      <div class="card w-full max-w-md card-stock shadow-xl">
        <div class="card-body items-center text-center">
          <h1 class="card-title font-display text-2xl">Hologram is wired up</h1>
          <p class="text-sm text-base-content/70">
            This page is served through the Phoenix endpoint, but rendered and
            made interactive by Hologram — the click handler below runs
            Elixir compiled to JavaScript, with no separate JS framework
            involved. Styled with daisyUI.
          </p>
          <div class="card-actions items-center gap-3 mt-4">
            <button id="increment" $click="increment" class="btn btn-primary">
              Increment
            </button>
            <button id="reset" $click="reset" class="btn btn-outline btn-secondary">
              Reset
            </button>
            <div id="count" class="badge badge-lg badge-secondary">{@count}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def action(:increment, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end

  def action(:reset, _params, component) do
    put_state(component, :count, 0)
  end
end
