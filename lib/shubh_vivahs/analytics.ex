defmodule ShubhVivahs.Analytics do
  @moduledoc """
  Real page-visit metrics for `AdminAnalyticsPage`, sourced from `PageVisit`
  rows written by `ShubhVivahsWeb.Plugs.PageVisitLogger` for every
  Hologram page view — both a fresh browser load and a subsequent
  client-side navigation. There's no IP geolocation database in the app, so
  unlike the page's old sample data this reports real top IPs rather than
  invented regions.
  """

  import Ecto.Query

  require Logger

  alias ShubhVivahs.Analytics.PageVisit
  alias ShubhVivahs.Engagement.Comment
  alias ShubhVivahs.PromoRequests.PromoRequest
  alias ShubhVivahs.Repo

  @top_urls_limit 5
  @top_ips_limit 4
  @visit_log_page_size 50
  @export_limit 5000

  # No DST, fixed +5:30 offset - a full tz database isn't needed for this.
  @ist_offset_seconds 5 * 3600 + 30 * 60

  @sortable_fields %{
    "at" => :inserted_at,
    "ip" => :ip,
    "path" => :path,
    "referrer" => :referrer,
    "method" => :method,
    "duration_ms" => :duration_ms
  }
  @default_sort_by "at"
  @default_sort_dir "desc"

  @doc "Converts a naive UTC timestamp (as stored) to India Standard Time, for display."
  @spec to_ist(NaiveDateTime.t()) :: NaiveDateTime.t()
  def to_ist(naive_utc), do: NaiveDateTime.add(naive_utc, @ist_offset_seconds, :second)

  @doc """
  Records one page visit. Never raises - a tracking failure must not break
  the response it's piggybacking on. Broadcasts on `:page_visits_changed` so
  any open AdminAnalyticsPage refreshes right away instead of waiting for its
  own fallback timer - see that page's `:visits_changed` action.
  """
  @spec record_visit(map) :: :ok | :error
  def record_visit(attrs) do
    %PageVisit{}
    |> PageVisit.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _} ->
        Hologram.Realtime.broadcast_action(:page_visits_changed, :visits_changed)
        :ok

      {:error, changeset} ->
        Logger.warning("page visit tracking failed: #{inspect(changeset.errors)}")
        :error
    end
  rescue
    error ->
      Logger.warning("page visit tracking raised: #{inspect(error)}")
      :error
  end

  @doc """
  Turns raw filter params (string keys, as submitted from the filter form or
  the CSV export query string) into the typed filter map every other
  function here expects.
  """
  @spec parse_filters(map) :: map
  def parse_filters(params) do
    %{
      from: parse_date(params["from"]),
      to: parse_date(params["to"]),
      path: blank_to_nil(params["path"]),
      ip: blank_to_nil(params["ip"]),
      method: blank_to_nil(params["method"]),
      referrer: blank_to_nil(params["referrer"]),
      min_duration_ms: parse_int(params["min_duration_ms"]),
      max_duration_ms: parse_int(params["max_duration_ms"]),
      sort_by: parse_sort_by(params["sort_by"]),
      sort_dir: parse_sort_dir(params["sort_dir"]),
      page: parse_page(params["page"])
    }
  end

  @doc """
  Builds every figure `AdminAnalyticsPage` shows for the given filters.
  Date range defaults to the last 24 hours when `:from`/`:to` are absent,
  matching the dashboard's original "Live 24h" framing.
  """
  @spec dashboard(map) :: map
  def dashboard(filters \\ %{}) do
    filters = filters |> with_sort_defaults() |> Map.put_new(:page, 1)
    range = resolve_range(filters)
    scoped = base_query(range, filters)
    visit_page = visit_log_page(filters)

    %{
      range_label: range_label(filters),
      total_page_views_all_time: Repo.aggregate(PageVisit, :count),
      total_in_range: Repo.aggregate(scoped, :count),
      top_urls: top_urls(scoped),
      unique_ip_count: unique_ip_count(scoped),
      top_ips: top_ips(scoped),
      visit_logs: visit_page.logs,
      visit_log_total: visit_page.total,
      visit_log_page: visit_page.page,
      visit_log_pages: visit_page.pages,
      visit_log_has_more?: visit_page.has_more?,
      avg_duration_ms: avg_duration_ms(scoped),
      traffic_growth_pct: traffic_growth_pct(range, filters),
      premium_activations: premium_activations(),
      comments_posted: Repo.aggregate(Comment, :count),
      distinct_paths: distinct_paths(),
      distinct_ips: distinct_ips(),
      distinct_methods: distinct_methods(),
      distinct_referrers: distinct_referrers(),
      duration_range: duration_range(range, filters),
      sort_by: filters.sort_by,
      sort_dir: filters.sort_dir,
      export_url: export_url(filters),
      refreshed_at: NaiveDateTime.utc_now() |> to_ist() |> Calendar.strftime("%H:%M:%S")
    }
  end

  @doc """
  Fetches one page of the visit log for the given filters, without the rest
  of `dashboard/1`'s figures - used both by `dashboard/1` itself and by
  AdminAnalyticsPage's infinite-scroll "load more" command, which only ever
  needs the next batch of rows.
  """
  @spec visit_log_page(map) :: map
  def visit_log_page(filters) do
    filters = filters |> with_sort_defaults() |> Map.put_new(:page, 1)
    range = resolve_range(filters)
    scoped = base_query(range, filters)

    total = Repo.aggregate(scoped, :count)
    pages = max(ceil(total / @visit_log_page_size), 1)
    page = min(max(filters.page, 1), pages)

    %{
      logs: visit_logs(scoped, filters, page),
      total: total,
      page: page,
      pages: pages,
      has_more?: page < pages
    }
  end

  @doc "Every distinct path a visit has been recorded for, for the filter dropdown."
  @spec distinct_paths() :: [String.t()]
  def distinct_paths do
    PageVisit |> select([v], v.path) |> distinct(true) |> order_by([v], asc: v.path) |> Repo.all()
  end

  @doc "Every distinct visitor IP a visit has been recorded for, for the filter dropdown."
  @spec distinct_ips() :: [String.t()]
  def distinct_ips do
    PageVisit |> select([v], v.ip) |> distinct(true) |> order_by([v], asc: v.ip) |> Repo.all()
  end

  @doc "Every distinct HTTP method a visit has been recorded with, for the filter dropdown."
  @spec distinct_methods() :: [String.t()]
  def distinct_methods do
    PageVisit
    |> select([v], v.method)
    |> distinct(true)
    |> order_by([v], asc: v.method)
    |> Repo.all()
  end

  @doc """
  Every distinct non-empty referrer a visit has been recorded with, for the
  filter dropdown. Excludes the null/"direct" case - the dropdown adds that
  option itself, since it represents an absence of data rather than a real
  value to look up.
  """
  @spec distinct_referrers() :: [String.t()]
  def distinct_referrers do
    PageVisit
    |> where([v], not is_nil(v.referrer))
    |> select([v], v.referrer)
    |> distinct(true)
    |> order_by([v], asc: v.referrer)
    |> Repo.all()
  end

  @doc "Rows for the CSV export, matching the same filters as the dashboard, most recent first."
  @spec export_rows(map) :: [PageVisit.t()]
  def export_rows(filters) do
    filters = with_sort_defaults(filters)
    range = resolve_range(filters)

    range
    |> base_query(filters)
    |> order_by(^sort_expr(filters))
    |> limit(@export_limit)
    |> Repo.all()
  end

  defp with_sort_defaults(filters) do
    filters
    |> Map.put_new(:sort_by, @default_sort_by)
    |> Map.put_new(:sort_dir, @default_sort_dir)
  end

  # Most non-date columns (ip, method, ...) have a lot of repeat values, so a
  # sort on just that field leaves ties in whatever order the DB feels like -
  # easy to mistake for "sorting did nothing". Breaking ties by recency keeps
  # the result stable and makes every sort visibly change something.
  defp sort_expr(filters) do
    field = Map.fetch!(@sortable_fields, filters.sort_by)
    primary = {sort_dir_atom(filters.sort_dir), field}

    if field == :inserted_at do
      [primary]
    else
      [primary, {:desc, :inserted_at}]
    end
  end

  defp sort_dir_atom("asc"), do: :asc
  defp sort_dir_atom(_), do: :desc

  defp export_url(filters) do
    optional_if_changed = %{
      "sort_by" => if(filters.sort_by != @default_sort_by, do: filters.sort_by),
      "sort_dir" => if(filters.sort_dir != @default_sort_dir, do: filters.sort_dir)
    }

    query =
      %{
        "from" => filters[:from] && Date.to_iso8601(filters[:from]),
        "to" => filters[:to] && Date.to_iso8601(filters[:to]),
        "path" => filters[:path],
        "ip" => filters[:ip],
        "method" => filters[:method],
        "referrer" => filters[:referrer],
        "min_duration_ms" => filters[:min_duration_ms] && to_string(filters[:min_duration_ms]),
        "max_duration_ms" => filters[:max_duration_ms] && to_string(filters[:max_duration_ms])
      }
      |> Map.merge(optional_if_changed)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})
      |> URI.encode_query()

    if query == "",
      do: "/admin/analytics/export.csv",
      else: "/admin/analytics/export.csv?" <> query
  end

  defp range_label(filters) do
    if is_nil(filters[:from]) and is_nil(filters[:to]) do
      "Live 24h"
    else
      "Selected Range"
    end
  end

  defp resolve_range(filters) do
    now = NaiveDateTime.utc_now()

    to_dt =
      case filters[:to] do
        %Date{} = d -> NaiveDateTime.new!(d, ~T[23:59:59])
        _ -> now
      end

    from_dt =
      case filters[:from] do
        %Date{} = d -> NaiveDateTime.new!(d, ~T[00:00:00])
        _ -> NaiveDateTime.add(now, -24 * 60 * 60, :second)
      end

    {from_dt, to_dt}
  end

  defp base_query({from_dt, to_dt}, filters) do
    PageVisit
    |> where([v], v.inserted_at >= ^from_dt and v.inserted_at <= ^to_dt)
    |> maybe_filter_path(filters[:path])
    |> maybe_filter_ip(filters[:ip])
    |> maybe_filter_method(filters[:method])
    |> maybe_filter_referrer(filters[:referrer])
    |> maybe_filter_min_duration(filters[:min_duration_ms])
    |> maybe_filter_max_duration(filters[:max_duration_ms])
  end

  defp maybe_filter_path(query, path) when path in [nil, ""], do: query
  defp maybe_filter_path(query, path), do: where(query, [v], v.path == ^path)

  defp maybe_filter_ip(query, ip) when ip in [nil, ""], do: query
  defp maybe_filter_ip(query, ip), do: where(query, [v], v.ip == ^ip)

  defp maybe_filter_method(query, method) when method in [nil, ""], do: query
  defp maybe_filter_method(query, method), do: where(query, [v], v.method == ^method)

  defp maybe_filter_referrer(query, referrer) when referrer in [nil, ""], do: query
  defp maybe_filter_referrer(query, "direct"), do: where(query, [v], is_nil(v.referrer))
  defp maybe_filter_referrer(query, referrer), do: where(query, [v], v.referrer == ^referrer)

  defp maybe_filter_min_duration(query, nil), do: query
  defp maybe_filter_min_duration(query, ms), do: where(query, [v], v.duration_ms >= ^ms)

  defp maybe_filter_max_duration(query, nil), do: query
  defp maybe_filter_max_duration(query, ms), do: where(query, [v], v.duration_ms <= ^ms)

  # The actual min/max response time among matching visits, deliberately
  # ignoring the min/max duration filters themselves (unlike base_query/2) -
  # this backs a hint next to those two fields, and a hint that only ever
  # reflected whatever you'd already typed into them would be useless.
  defp duration_range({from_dt, to_dt}, filters) do
    query =
      PageVisit
      |> where([v], v.inserted_at >= ^from_dt and v.inserted_at <= ^to_dt)
      |> maybe_filter_path(filters[:path])
      |> maybe_filter_ip(filters[:ip])
      |> maybe_filter_method(filters[:method])
      |> maybe_filter_referrer(filters[:referrer])
      |> select([v], {min(v.duration_ms), max(v.duration_ms)})

    case Repo.one(query) do
      {nil, nil} -> nil
      {min, max} -> %{min: min, max: max}
    end
  end

  defp top_urls(scoped) do
    scoped
    |> group_by([v], v.path)
    |> select([v], {v.path, count(v.id)})
    |> order_by([v], desc: count(v.id))
    |> limit(^@top_urls_limit)
    |> Repo.all()
    |> Enum.map(fn {path, count} -> %{path: path, count: count} end)
  end

  defp unique_ip_count(scoped) do
    scoped |> select([v], v.ip) |> distinct(true) |> Repo.all() |> length()
  end

  defp top_ips(scoped) do
    scoped
    |> group_by([v], v.ip)
    |> select([v], {v.ip, count(v.id)})
    |> order_by([v], desc: count(v.id))
    |> limit(^@top_ips_limit)
    |> Repo.all()
    |> Enum.map(fn {ip, count} -> %{ip: ip, count: count} end)
  end

  defp visit_logs(scoped, filters, page) do
    scoped
    |> order_by(^sort_expr(filters))
    |> limit(@visit_log_page_size)
    |> offset(^((page - 1) * @visit_log_page_size))
    |> Repo.all()
    |> Enum.map(&visit_log_view/1)
  end

  defp visit_log_view(visit) do
    %{
      at: visit.inserted_at |> to_ist() |> Calendar.strftime("%d %b %Y %H:%M:%S"),
      ip: visit.ip,
      path: visit.path,
      referrer: visit.referrer || "direct",
      method: visit.method,
      status: visit.status,
      duration_ms: visit.duration_ms || 0
    }
  end

  defp avg_duration_ms(scoped) do
    case Repo.aggregate(scoped, :avg, :duration_ms) do
      nil -> 0
      %Decimal{} = d -> d |> Decimal.to_float() |> round()
      n when is_number(n) -> round(n)
    end
  end

  defp traffic_growth_pct({from_dt, to_dt}, filters) do
    span = NaiveDateTime.diff(to_dt, from_dt, :second)
    prev_range = {NaiveDateTime.add(from_dt, -span, :second), from_dt}

    current = base_query({from_dt, to_dt}, filters) |> Repo.aggregate(:count)
    previous = prev_range |> base_query(filters) |> Repo.aggregate(:count)

    case previous do
      0 -> nil
      _ -> Float.round((current - previous) / previous * 100, 1)
    end
  end

  defp premium_activations do
    PromoRequest |> where(status: "approved") |> Repo.aggregate(:count)
  end

  defp parse_date(str) when is_binary(str) and str != "" do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp parse_sort_by(key) when is_map_key(@sortable_fields, key), do: key
  defp parse_sort_by(_), do: @default_sort_by

  defp parse_sort_dir("asc"), do: "asc"
  defp parse_sort_dir(_), do: @default_sort_dir

  defp parse_page(value) do
    case Integer.parse(to_string(value || "1")) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_int(str) when is_binary(str) and str != "" do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end
