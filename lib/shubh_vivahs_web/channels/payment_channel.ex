defmodule ShubhVivahsWeb.PaymentChannel do
  @moduledoc """
  Receives structured payment-confirmation events from the companion
  Android app (see `PaymentSocket` for the connection auth model). Two
  things happen with a valid, known-tier amount:

    1. It's recorded in `ShubhVivahs.PaymentStore`, so a visitor who
       clicks UpgradePage's "Confirm Payment" button gets a synchronous
       answer even if they weren't watching at the exact moment this
       arrived.
    2. It's rebroadcast into Hologram's realtime layer via
       `Hologram.Realtime.broadcast_action/3`, so a tab that already has
       /upgrade open updates live without needing to click anything.

  The Android app is expected to have already parsed its own bank SMS
  text on-device and send just the extracted amount — this channel does
  not parse raw SMS text itself, and never sees the SMS body.

  Matching an incoming payment to "the visitor who should see it as paid"
  is amount-only, on purpose (see UpgradePage's moduledoc): every browser
  currently showing (or checking) that amount tier gets marked paid. Two
  people paying the same amount around the same time would both see
  confirmation — a known, accepted gap until real per-visitor accounts
  exist.
  """

  use Phoenix.Channel

  alias ShubhVivahs.PaymentStore
  alias ShubhVivahsWeb.Hologram.Pages.UpgradePage

  @impl true
  def join("payments:lobby", _params, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in("payment_sms", %{"amount" => raw_amount}, socket) do
    case parse_amount(raw_amount) do
      {:ok, amount} ->
        if amount in UpgradePage.amount_tiers() do
          PaymentStore.record_payment(amount)

          Hologram.Realtime.broadcast_action(
            {:payment_received, amount},
            :payment_confirmed,
            %{amount: amount}
          )
        end

      :error ->
        :ok
    end

    {:noreply, socket}
  end

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  defp parse_amount(amount) when is_integer(amount), do: {:ok, amount}

  defp parse_amount(amount) when is_binary(amount) do
    case Integer.parse(amount) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_amount(_amount), do: :error
end
