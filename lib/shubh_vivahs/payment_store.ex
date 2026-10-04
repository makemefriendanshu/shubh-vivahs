defmodule ShubhVivahs.PaymentStore do
  @moduledoc """
  Minimal in-memory record of the most recent UPI payment reported per
  amount tier, fed by `ShubhVivahsWeb.PaymentChannel`. Backs the
  "Confirm Payment" button on `UpgradePage`: the live PubSub push (via
  `Hologram.Realtime.broadcast_action/3`) only reaches a tab that is
  already open and subscribed at the exact moment the payment is
  reported, so a visitor who missed that window, or opened the page
  after paying, needs a way to explicitly ask "has my payment landed
  yet" and get a synchronous answer.

  Not persisted across restarts, and not scoped per visitor — there is
  no account system, so recording is amount-only, the same known gap as
  the live-push path. A payment only counts as "recent" for
  `@recent_window_ms`, so a payment from hours ago does not make a later
  visitor selecting the same tier see a false "paid" result.
  """

  use GenServer

  @recent_window_ms 15 * 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc "Records that `amount` was just paid, at the current time."
  @spec record_payment(integer) :: :ok
  def record_payment(amount) when is_integer(amount) do
    GenServer.cast(__MODULE__, {:record, amount, System.monotonic_time(:millisecond)})
  end

  @doc """
  Clears a recorded payment for `amount`, e.g. when an admin revokes a
  promo request they'd previously approved. Amount-only, same as
  `record_payment/1` — revoking would also clear a real payment for the
  same tier reported around the same time, a known gap.
  """
  @spec revoke_payment(integer) :: :ok
  def revoke_payment(amount) when is_integer(amount) do
    GenServer.cast(__MODULE__, {:revoke, amount})
  end

  @doc "Returns true if `amount` was recorded as paid within the recent window."
  @spec recently_paid?(integer) :: boolean
  def recently_paid?(amount) when is_integer(amount) do
    GenServer.call(__MODULE__, {:check, amount, System.monotonic_time(:millisecond)})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:record, amount, at}, state) do
    {:noreply, Map.put(state, amount, at)}
  end

  @impl true
  def handle_cast({:revoke, amount}, state) do
    {:noreply, Map.delete(state, amount)}
  end

  @impl true
  def handle_call({:check, amount, now}, _from, state) do
    paid? =
      case Map.get(state, amount) do
        nil -> false
        recorded_at -> now - recorded_at <= @recent_window_ms
      end

    {:reply, paid?, state}
  end
end
