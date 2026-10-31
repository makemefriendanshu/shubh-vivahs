defmodule ShubhVivahsWeb.Plugs.PageVisitLogger do
  @moduledoc """
  Records a `ShubhVivahs.Analytics.PageVisit` row for every Hologram
  page view, so `AdminAnalyticsPage` can show real top URLs, unique IPs,
  and a visit log instead of sample data.

  Runs in the endpoint pipeline before `Hologram.Router`, since a page view
  reaches the app two different ways that router alone can't unify:

    * a fresh browser load, a plain `GET` to the page's own route
      (e.g. `/admin/analytics`), resolved the same way `Hologram.Router`
      resolves it - via `PageModuleResolver`;
    * a subsequent client-side navigation (clicking a `Link`), a `POST` to
      `/hologram/page/:module` carrying the target page's params in the
      query string rather than the path, so the friendly path has to be
      rebuilt from the page's declared route pattern.

  Any other request (static assets, the video/thumbnail controllers,
  Hologram's own command/ping/sse/websocket endpoints) is passed through
  untouched.
  """

  import Plug.Conn

  alias Hologram.Router.PageModuleResolver
  alias ShubhVivahs.Analytics

  @spec init(keyword) :: keyword
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword) :: Plug.Conn.t()
  def call(conn, _opts) do
    # Hologram.Router itself no-ops the same way when disabled (its own
    # supervision tree - including PageModuleResolver's persistent_term -
    # isn't started then), so mirror that guard here too: without it,
    # PageModuleResolver.resolve/1 raises ArgumentError ("no persistent term
    # stored with this key") on every request, wherever Hologram isn't
    # running - not just under `mix test`, but any environment that boots
    # without HOLOGRAM_START=1.
    if Hologram.enabled?() do
      case resolve_page_path(conn) do
        nil -> conn
        path -> track(conn, path)
      end
    else
      conn
    end
  end

  defp track(conn, path) do
    started_at = System.monotonic_time()
    ip = format_ip(conn.remote_ip)
    referrer = conn |> get_req_header("referer") |> List.first()

    register_before_send(conn, fn conn ->
      Analytics.record_visit(%{
        path: path,
        ip: ip,
        referrer: referrer,
        method: conn.method,
        status: conn.status,
        duration_ms: duration_ms(started_at)
      })

      conn
    end)
  end

  defp resolve_page_path(%Plug.Conn{method: "GET"} = conn) do
    # PageModuleResolver.resolve/1 returns `false` (not `nil`) for no match,
    # same as Hologram.Router's own `if page_module = resolve(...)` check.
    if PageModuleResolver.resolve(conn.request_path) do
      conn.request_path
    end
  end

  defp resolve_page_path(
         %Plug.Conn{method: "POST", path_info: ["hologram", "page", module_str]} = conn
       ) do
    page_module = Module.safe_concat([module_str])
    conn = fetch_query_params(conn)
    build_friendly_path(page_module.__route__(), conn.query_params)
  rescue
    ArgumentError -> nil
  end

  defp resolve_page_path(_conn), do: nil

  defp build_friendly_path(route_pattern, query_params) do
    route_pattern
    |> String.split("/")
    |> Enum.map(fn
      ":" <> key -> Map.get(query_params, key, ":" <> key)
      segment -> segment
    end)
    |> Enum.join("/")
  end

  defp format_ip(remote_ip), do: remote_ip |> :inet.ntoa() |> List.to_string()

  defp duration_ms(started_at) do
    System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)
  end
end
