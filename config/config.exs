# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :shubh_vivahs,
  ecto_repos: [ShubhVivahs.Repo],
  generators: [timestamp_type: :utc_datetime]

# busy_timeout raised from the 2000ms default: SQLite allows only one writer at a
# time, so two connections racing to write (e.g. two rapid like-toggle clicks) need
# to be able to wait out a queued write transaction rather than give up early with
# Exqlite.Error. Read-only queries are unaffected (WAL allows concurrent readers),
# so this doesn't touch normal page-load throughput the way pool_size: 1 would.
config :shubh_vivahs, ShubhVivahs.Repo,
  adapter: Ecto.Adapters.SQLite3,
  busy_timeout: 10_000

# Configure the endpoint
config :shubh_vivahs, ShubhVivahsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ShubhVivahsWeb.ErrorHTML, json: ShubhVivahsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ShubhVivahs.PubSub,
  live_view: [signing_salt: "NiIwR9sX"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :shubh_vivahs, ShubhVivahs.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  shubh_vivahs: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  shubh_vivahs: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
