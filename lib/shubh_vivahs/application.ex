defmodule ShubhVivahs.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ShubhVivahs.Repo,
      ShubhVivahsWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:shubh_vivahs, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ShubhVivahs.PubSub},
      ShubhVivahs.FaceDetection.ModelServer,
      ShubhVivahs.PaymentStore,
      {Task.Supervisor, name: ShubhVivahs.TaskSupervisor},
      # Start to serve requests, typically the last entry
      ShubhVivahsWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ShubhVivahs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ShubhVivahsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
