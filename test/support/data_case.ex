defmodule ShubhVivahs.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring access to the
  application's data layer.

  Such tests rely on `ShubhVivahs.Repo` and also enable the SQL
  sandbox, so changes done to the database are reverted at the end of
  every test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias ShubhVivahs.Repo
    end
  end

  setup tags do
    ShubhVivahs.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ShubhVivahs.Repo, shared: not tags[:async])
    ExUnit.Callbacks.on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
