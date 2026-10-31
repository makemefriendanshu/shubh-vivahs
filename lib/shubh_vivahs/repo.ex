defmodule ShubhVivahs.Repo do
  use Ecto.Repo,
    otp_app: :shubh_vivahs,
    adapter: Ecto.Adapters.SQLite3
end
