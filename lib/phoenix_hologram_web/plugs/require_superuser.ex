defmodule PhoenixHologramWeb.Plugs.RequireSuperuser do
  @moduledoc """
  Gates the plain (non-Hologram) admin endpoints that back the
  superuser-only admin pages — `AdminAnalyticsCsvController`'s CSV export
  and `FaceThumbnailController`'s face crops — behind the same login used
  by `PhoenixHologramWeb.Hologram.Middleware.RequireSuperuser`. Without
  this, those endpoints would stay reachable by URL even after the pages
  that link to them were locked down.

  Reads the Hologram-managed user id straight out of the Phoenix session
  (the same key `put_user_id/2` writes to) since these routes sit outside
  Hologram's own request pipeline and so never see a `%Hologram.Server{}`.
  """

  import Plug.Conn

  alias PhoenixHologram.Accounts

  @spec init(keyword) :: keyword
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword) :: Plug.Conn.t()
  def call(conn, _opts) do
    with user_id when not is_nil(user_id) <- Hologram.Runtime.Session.get_user_id(conn),
         %Accounts.User{} = user <- Accounts.get_user(user_id),
         true <- Accounts.superuser?(user) do
      conn
    else
      _not_authorized ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.text("Forbidden")
        |> halt()
    end
  end
end
