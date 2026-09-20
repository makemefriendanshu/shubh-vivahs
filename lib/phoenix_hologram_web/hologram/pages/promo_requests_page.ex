defmodule PhoenixHologramWeb.Hologram.Pages.PromoRequestsPage do
  @moduledoc """
  Standalone "Promo Requests" review queue for UpgradePage's "Know the
  founder personally?" free-access requests — approving one here grants
  the requested tier through `PhoenixHologram.PromoRequests.approve_promo_request/1`,
  the only place that actually happens (submitting a request no longer
  grants anything by itself). Split out of AdminMoviesPage into its own
  page/route, reached from the "Promo Requests" link in DefaultLayout's
  site-wide nav bar.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias PhoenixHologram.PromoRequests
  alias PhoenixHologramWeb.Hologram.Middleware.RequireSuperuser
  alias PhoenixHologramWeb.Hologram.Pages.AdminMoviesPage

  route "/admin/promo-requests"

  middleware RequireSuperuser

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server) do
    component = put_state(component, :promo_requests, PromoRequests.list_promo_requests_view())

    # Every open PromoRequestsPage tab picks up new/approved/rejected promo
    # requests live — PromoRequests broadcasts on this channel from
    # create_promo_request/1, approve_promo_request/1, and
    # reject_promo_request/1, each carrying the freshly formatted list.
    server = put_subscription(server, :promo_requests_changed)

    {component, server}
  end

  def action(:approve_promo_request, params, component) do
    put_command(component, :approve_promo_request, id: params.id)
  end

  def action(:reject_promo_request, params, component) do
    put_command(component, :reject_promo_request, id: params.id)
  end

  def action(:promo_requests_reloaded, params, component) do
    put_state(component, :promo_requests, params.requests)
  end

  # These commands don't need to return the reloaded list themselves
  # (via put_action) — the context functions already broadcast it on
  # :promo_requests_changed, which this page (like every other open one)
  # is subscribed to, so the update arrives the same way regardless of
  # which tab triggered it.
  def command(:approve_promo_request, %{id: id}, server) do
    PromoRequests.approve_promo_request(id)
    server
  end

  def command(:reject_promo_request, %{id: id}, server) do
    PromoRequests.reject_promo_request(id)
    server
  end

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
            Promo Requests
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <div class="flex justify-center mb-4">
          {%if @promo_requests != []}
            <span class="badge badge-outline badge-primary">
              {Enum.count(@promo_requests, &(&1.status == "pending"))} pending
            </span>
          {/if}
        </div>
        <div class="gold-divider w-24 mx-auto mb-6"></div>

        {%if @promo_requests == []}
          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <p class="text-base-content/70">No free-access requests yet.</p>
            </div>
          </div>
        {%else}
          <div class="card card-stock shadow-xl overflow-x-auto">
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th>When</th>
                  <th>Description</th>
                  <th>Amount</th>
                  <th>Code</th>
                  <th>Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {%for request <- @promo_requests}
                  <tr>
                    <td class="text-xs whitespace-nowrap">{request.requested_at}</td>
                    <td class="text-sm max-w-[16rem]">{request.description}</td>
                    <td class="text-sm whitespace-nowrap">&#8377;{request.amount}</td>
                    <td class="text-xs font-mono">{request.code}</td>
                    <td>
                      <span class={
                        case request.status do
                          "approved" -> "badge badge-success"
                          "rejected" -> "badge badge-error"
                          _ -> "badge badge-warning"
                        end
                      }>
                        {request.status}
                      </span>
                    </td>
                    <td class="whitespace-nowrap">
                      {%if request.status == "pending"}
                        <button $click={:approve_promo_request, id: request.id} class="btn btn-xs btn-primary">
                          Approve
                        </button>
                        <button $click={:reject_promo_request, id: request.id} class="btn btn-xs btn-outline">
                          Reject
                        </button>
                      {/if}
                      {%if request.status == "rejected"}
                        <button $click={:approve_promo_request, id: request.id} class="btn btn-xs btn-primary">
                          Approve Anyway
                        </button>
                      {/if}
                      {%if request.status == "approved"}
                        <button $click={:reject_promo_request, id: request.id} class="btn btn-xs btn-outline">
                          Revoke
                        </button>
                      {/if}
                    </td>
                  </tr>
                {/for}
              </tbody>
            </table>
          </div>
        {/if}

        <div class="flex justify-center mt-8">
          <Link to={AdminMoviesPage} class="btn btn-outline btn-block gap-2">
            <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
            Back To Admin Portal
          </Link>
        </div>
      </div>
    </div>
    """
  end
end
