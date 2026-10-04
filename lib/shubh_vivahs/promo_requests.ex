defmodule ShubhVivahs.PromoRequests do
  @moduledoc """
  "Free acquaintance privilege" requests submitted from UpgradePage's
  "Know the founder personally?" form. Every request starts `"pending"`
  and grants nothing by itself — approving one here is what actually
  unlocks the requested amount tier, via the same `PaymentStore` +
  `Hologram.Realtime.broadcast_action/3` path a real UPI payment uses
  (see `ShubhVivahsWeb.PaymentChannel`), so an approved request is
  indistinguishable from a real payment to UpgradePage's live-push and
  "Confirm Payment" logic.
  """

  import Ecto.Query

  alias ShubhVivahs.PromoRequests.PromoRequest
  alias ShubhVivahs.Repo

  @doc """
  Creates a pending promo request and broadcasts the change on
  `:promo_requests_changed`, so any open PromoRequestsPage tab picks up
  the new row live instead of only on its next manual reload/action.
  """
  def create_promo_request(attrs) do
    with {:ok, request} <- %PromoRequest{} |> PromoRequest.changeset(attrs) |> Repo.insert() do
      broadcast_requests_changed()
      {:ok, request}
    end
  end

  @doc "Lists every promo request, most recent first."
  def list_promo_requests do
    Repo.all(from p in PromoRequest, order_by: [desc: p.inserted_at])
  end

  @doc "Lists every promo request as plain view-model maps, for PromoRequestsPage's table."
  def list_promo_requests_view do
    list_promo_requests()
    |> Enum.map(fn request ->
      %{
        id: request.id,
        description: request.description,
        amount: request.amount,
        code: request.code,
        status: request.status,
        requested_at: Calendar.strftime(request.inserted_at, "%d %b %Y %H:%M")
      }
    end)
  end

  @doc "Returns the status string for the request with this code, or nil if no such code exists."
  def get_status_by_code(code) do
    case get_by_code(code) do
      nil -> nil
      request -> request.status
    end
  end

  @doc "Returns the full request for this code, or nil if no such code exists."
  def get_by_code(code) do
    Repo.get_by(PromoRequest, code: code)
  end

  @doc """
  Approves a pending request: marks it approved and grants the
  requested amount tier exactly as a real UPI payment would — recording
  it in PaymentStore and broadcasting live to any open /upgrade tab.
  Also broadcasts on the request's own `{:promo_status, code}` channel
  (UpgradePage subscribes to that specific code when it's generated),
  so the exact submitter sees "approved" even if they'd switched to a
  different amount tier than the one they requested.
  """
  def approve_promo_request(id) do
    with {:ok, request} <- update_status(id, "approved") do
      ShubhVivahs.PaymentStore.record_payment(request.amount)

      Hologram.Realtime.broadcast_action(
        {:payment_received, request.amount},
        :payment_confirmed,
        %{amount: request.amount}
      )

      broadcast_promo_status(request)
      broadcast_requests_changed()

      {:ok, request}
    end
  end

  @doc """
  Rejects a request. If it was previously `"approved"`, this also
  revokes the grant — clearing the amount from PaymentStore so a
  visitor's later "Confirm Payment" click no longer reports it as paid.
  Broadcasts on `{:promo_status, code}` either way, so a rejection is
  visible to the submitter live, not just discoverable by chance.
  """
  def reject_promo_request(id) do
    was_approved? = Repo.get!(PromoRequest, id).status == "approved"

    with {:ok, request} <- update_status(id, "rejected") do
      if was_approved?, do: ShubhVivahs.PaymentStore.revoke_payment(request.amount)
      broadcast_promo_status(request)
      broadcast_requests_changed()
      {:ok, request}
    end
  end

  defp broadcast_promo_status(request) do
    Hologram.Realtime.broadcast_action(
      {:promo_status, request.code},
      :promo_status_updated,
      %{status: request.status}
    )
  end

  # Bare-atom channel any PromoRequestsPage instance subscribes to (see its
  # init/3) — pushes the freshly formatted list directly in the broadcast
  # payload so a subscribed page just applies it, no extra command round
  # trip needed to re-fetch.
  defp broadcast_requests_changed do
    Hologram.Realtime.broadcast_action(
      :promo_requests_changed,
      :promo_requests_reloaded,
      %{requests: list_promo_requests_view()}
    )
  end

  defp update_status(id, status) do
    PromoRequest
    |> Repo.get!(id)
    |> PromoRequest.changeset(%{status: status})
    |> Repo.update()
  end
end
