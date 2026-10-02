import Config

config :shubh_vivahs, ShubhVivahs.Repo,
  database: Path.expand("../priv/face_detection/shubh_vivahs_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :shubh_vivahs, ShubhVivahsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "sbwO18j0rJQy23NZI4eYfEwyNu8LEDG10Lrcnn4u6PH/yPgiaVpKjqU5v9pPK0/6",
  server: false

# In test we don't send emails
config :shubh_vivahs, ShubhVivahs.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
