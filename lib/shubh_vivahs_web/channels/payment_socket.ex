defmodule ShubhVivahsWeb.PaymentSocket do
  @moduledoc """
  WebSocket entry point for the companion Android app that reads incoming
  UPI payment-confirmation SMS notifications and forwards the extracted
  amount here, so UpgradePage can show a live "paid" confirmation instead
  of relying solely on a manual WhatsApp message. This is unrelated to
  Hologram's own internal client-server socket — a separate, narrowly
  scoped channel for one external device to report structured payment
  events, not a general-purpose API.

  Auth is a single static shared-secret token (`config :shubh_vivahs,
  :payment_socket_token`, set via the `PAYMENT_SOCKET_TOKEN` env var in
  `config/runtime.exs`) checked at connect time — there is no per-user
  auth system in this app, so this is the entire authorization model for
  now. Anyone holding the token can claim any tracked amount was paid;
  rotate the token if it ever leaks. If the token isn't configured at
  all (e.g. forgotten in production), every connection is rejected —
  fails closed, not open.
  """

  use Phoenix.Socket

  channel "payments:lobby", ShubhVivahsWeb.PaymentChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case Application.get_env(:shubh_vivahs, :payment_socket_token) do
      configured when is_binary(configured) ->
        if Plug.Crypto.secure_compare(token, configured) do
          {:ok, socket}
        else
          :error
        end

      _missing ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil
end
