defmodule PhoenixHologramWeb.Hologram.Pages.AdminAnalyticsPage do
  @moduledoc """
  Admin "analytics" dashboard: top visited URLs, unique visitor IPs, and a
  detailed visit log, all backed by real `PhoenixHologram.Analytics.PageVisit`
  rows recorded by `PhoenixHologramWeb.Plugs.PageVisitLogger` for every
  Hologram page view. Only visits recorded since that plug shipped are
  counted - there's no backfill for earlier traffic. There's no IP
  geolocation database in the app, so the "unique IPs" breakdown shows real
  top IPs rather than invented regions. The date/link/IP filters and the CSV
  export both apply to the same query. Reached from the "Admin Analytics"
  link in DefaultLayout's site-wide nav bar.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias PhoenixHologram.Analytics
  alias PhoenixHologramWeb.Hologram.Middleware.RequireSuperuser
  alias PhoenixHologramWeb.Hologram.Pages.AdminMoviesPage

  @donut_colors [
    "var(--color-primary)",
    "var(--color-secondary)",
    "var(--color-accent)",
    "var(--color-info)"
  ]
  @donut_other_color "var(--color-base-300, #d8cbb0)"

  route "/admin/analytics"

  middleware RequireSuperuser

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  @filter_keys [
    :from,
    :to,
    :path,
    :ip,
    :method,
    :referrer,
    :min_duration_ms,
    :max_duration_ms,
    :sort_by,
    :sort_dir,
    :page
  ]

  def init(_params, component, server) do
    dashboard = Analytics.dashboard(%{})

    filters = %{
      from: "",
      to: "",
      path: "",
      ip: "",
      method: "",
      referrer: "",
      min_duration_ms: "",
      max_duration_ms: "",
      sort_by: dashboard.sort_by,
      sort_dir: dashboard.sort_dir,
      page: dashboard.visit_log_page
    }

    component =
      component
      |> put_view_state(dashboard, filters, build_view(dashboard))
      |> put_state(:loading_more?, false)
      |> put_state(:filters_visible?, true)

    # Analytics.record_visit/1 broadcasts here on every page view site-wide,
    # so any open dashboard refreshes right away - the 15s timer is just a
    # fallback in case a broadcast is ever missed (e.g. a dropped connection).
    server = put_subscription(server, :page_visits_changed)

    {component, server}
  end

  # Pure client-side UI toggle - the field values underneath are untouched,
  # so this never needs a server round trip.
  def action(:toggle_filters, _params, component) do
    put_state(component, :filters_visible?, not component.state.filters_visible?)
  end

  # Keeps whatever column sort is already active; new filter criteria
  # restarts pagination.
  def action(:apply_filters, params, component) do
    filters = component.state.filters

    overrides = %{
      from: params.event["from"],
      to: params.event["to"],
      path: params.event["path"],
      ip: params.event["ip"],
      method: params.event["method"],
      referrer: params.event["referrer"],
      min_duration_ms: params.event["min_duration_ms"],
      max_duration_ms: params.event["max_duration_ms"],
      page: 1
    }

    put_command(component, :load_dashboard, command_params(filters, overrides))
  end

  # Resets every filter field back to blank in one click, rather than making
  # the admin clear all eight by hand - and the column sort back to its
  # default (most-recent-first), since a sort picked while filtering is as
  # much a "narrowed view" as the filters themselves.
  def action(:clear_filters, _params, component) do
    filters = component.state.filters

    overrides = %{
      from: "",
      to: "",
      path: "",
      ip: "",
      method: "",
      referrer: "",
      min_duration_ms: "",
      max_duration_ms: "",
      sort_by: "at",
      sort_dir: "desc",
      page: 1
    }

    put_command(component, :load_dashboard, command_params(filters, overrides))
  end

  # Clicking the already-sorted column flips direction; clicking a different
  # one sorts it ascending. Keeps the current filters as-is. A new sort order
  # restarts pagination - whatever page you were on may not even exist under
  # the new order.
  def action(:sort_by_column, params, component) do
    filters = component.state.filters

    next_dir =
      if filters.sort_by == params.field and filters.sort_dir == "asc" do
        "desc"
      else
        "asc"
      end

    overrides = %{sort_by: params.field, sort_dir: next_dir, page: 1}
    put_command(component, :load_dashboard, command_params(filters, overrides))
  end

  # Fired the moment any visitor's page load is recorded elsewhere on the
  # site (Analytics.record_visit/1 broadcasts on :page_visits_changed, which
  # init/3 subscribes to), so the dashboard updates within roughly a second
  # instead of waiting on the :auto_refresh fallback timer below.
  def action(:visits_changed, _params, component), do: refresh_dashboard(component)

  # Fallback safety net in case a broadcast above is ever missed (e.g. the
  # realtime connection dropped and reconnected in between) - fires every
  # 60s from the auto-refresh script near the template's end.
  def action(:auto_refresh, _params, component), do: refresh_dashboard(component)

  # Fired by the polling script near the template's end, once the sentinel
  # element at the bottom of the visit log scrolls near the viewport. Guards
  # against firing again while a load is already in flight, or once every
  # matching row has already been loaded (the sentinel's own data attributes
  # drive that same guard client-side, so this is belt-and-suspenders).
  def action(:load_more_visits, _params, component) do
    dashboard = component.state.dashboard

    if component.state.loading_more? or not dashboard.visit_log_has_more? do
      component
    else
      filters = component.state.filters
      overrides = %{page: dashboard.visit_log_page + 1}

      component
      |> put_state(:loading_more?, true)
      |> put_command(:load_more_visits, command_params(filters, overrides))
    end
  end

  # Just assigns state - build_view/1 already ran server-side in the command
  # below. Enum.max/Float.round (inside build_view) fail with a client-side
  # FunctionClauseError when they run compiled to JS instead of natively, so
  # that math must never run from an action - only from init/command.
  def action(:dashboard_loaded, params, component) do
    resync_filter_selects()

    if params.preserve_rows do
      put_stats_only(component, params.dashboard, params.filters, params.view)
    else
      component
      |> put_view_state(params.dashboard, params.filters, params.view)
      |> put_state(:loading_more?, false)
    end
  end

  # Appends the next batch to what's already on screen, instead of replacing
  # it - the whole point of infinite scroll over pagination.
  def action(:more_visits_loaded, params, component) do
    rows = component.state.visit_log_rows ++ params.rows

    dashboard =
      component.state.dashboard
      |> Map.put(:visit_log_page, params.page)
      |> Map.put(:visit_log_has_more?, params.has_more?)

    component
    |> put_state(:dashboard, dashboard)
    |> put_state(:visit_log_rows, rows)
    |> put_state(:loading_more?, false)
  end

  # Builds the params for the :load_dashboard/:load_more_visits commands:
  # every current filter, with `overrides` layered on top. Runs client-side,
  # so it is plain map work only - the actual query happens in the command.
  # preserve_rows defaults to false - only refresh_dashboard/1 below ever
  # needs to override it.
  defp command_params(filters, overrides) do
    filters
    |> Map.take(@filter_keys)
    |> Map.put(:preserve_rows, false)
    |> Map.merge(Map.new(overrides))
  end

  # Skips the refresh only while a load is already in flight. Once the admin
  # has scrolled past the first batch via infinite scroll, this used to skip
  # entirely - which meant the whole "Live" indicator silently froze the
  # moment you scrolled, forever, since nothing ever re-enabled it. Now it
  # still refreshes the stats (top URLs, unique IPs, counts, the "updated
  # HH:MM:SS" timestamp) every time either way; only the visit log rows and
  # scroll position are left untouched while scrolled, via preserve_rows, so
  # it still never yanks the admin out of what they were reading.
  defp refresh_dashboard(component) do
    if component.state.loading_more? do
      component
    else
      filters = component.state.filters
      scrolled_past_first_page? = component.state.dashboard.visit_log_page > 1
      overrides = %{page: 1, preserve_rows: scrolled_past_first_page?}
      put_command(component, :load_dashboard, command_params(filters, overrides))
    end
  end

  # Used only by a background refresh that landed while the admin was
  # scrolled past the first batch: updates every stat (top URLs, unique IPs,
  # counts, refreshed_at) but keeps the currently-loaded visit log rows and
  # page number exactly as they were, so it can never yank their scroll
  # position or discard rows they already loaded via infinite scroll.
  defp put_stats_only(component, dashboard, filters, view) do
    old_dashboard = component.state.dashboard
    old_filters = component.state.filters

    dashboard =
      dashboard
      |> Map.put(:visit_logs, old_dashboard.visit_logs)
      |> Map.put(:visit_log_total, old_dashboard.visit_log_total)
      |> Map.put(:visit_log_page, old_dashboard.visit_log_page)
      |> Map.put(:visit_log_pages, old_dashboard.visit_log_pages)
      |> Map.put(:visit_log_has_more?, old_dashboard.visit_log_has_more?)

    filters = Map.put(filters, :page, old_filters.page)

    component
    |> put_state(:dashboard, dashboard)
    |> put_state(:filters, filters)
    |> put_state(:bars, view.bars)
    |> put_state(:regions, view.regions)
    |> put_state(:donut_style, view.donut_style)
    |> put_state(:loading_more?, false)
  end

  # A select element renders its live value from the "selected" attribute
  # only until the browser considers it user interacted (a manual click sets
  # that flag per the HTML spec) - after that point, patching the attribute
  # alone no longer moves the visible/functional selection, so Clear Filters
  # (and every other filter update) needs to force each dropdown's value
  # directly.
  #
  # JS.exec runs synchronously as this client-side action executes - before
  # Hologram has applied the new render to the DOM, not after. Reading
  # "option[selected]" at that point sees the *previous* render's markup, one
  # step behind the state this very action just computed (confirmed by
  # instrumenting real clicks: Apply showed blank selects, Clear Filters
  # showed the just-applied values - each one render behind). Deferring the
  # actual sync to a follow-up macrotask (setTimeout 0) lets Hologram's own
  # DOM patch land first, so this reads the render it is actually meant to.
  defp resync_filter_selects do
    JS.exec("""
    setTimeout(function () {
      ["analytics-path", "analytics-ip", "analytics-method", "analytics-referrer"].forEach(function (id) {
        var select = document.getElementById(id);
        if (!select) { return; }

        var selectedOption = select.querySelector("option[selected]");
        var wantedValue = selectedOption ? selectedOption.value : "";

        if (select.value !== wantedValue) {
          select.value = wantedValue;
        }
      });
    }, 0);
    """)
  end

  def command(:load_dashboard, params, server) do
    filters = params |> raw_filter_params() |> Analytics.parse_filters()
    dashboard = Analytics.dashboard(filters)

    put_action(server, :dashboard_loaded,
      dashboard: dashboard,
      filters: filters_for_state(params, dashboard),
      view: build_view(dashboard),
      preserve_rows: params.preserve_rows
    )
  end

  def command(:load_more_visits, params, server) do
    filters = params |> raw_filter_params() |> Analytics.parse_filters()
    visit_page = Analytics.visit_log_page(filters)

    put_action(server, :more_visits_loaded,
      rows: visit_page.logs,
      page: visit_page.page,
      has_more?: visit_page.has_more?
    )
  end

  # Reduces every filter param down to the string-keyed map Analytics.parse_filters/1
  # expects - shared by both commands above.
  defp raw_filter_params(params) do
    %{
      "from" => params.from,
      "to" => params.to,
      "path" => params.path,
      "ip" => params.ip,
      "method" => params.method,
      "referrer" => params.referrer,
      "min_duration_ms" => params.min_duration_ms,
      "max_duration_ms" => params.max_duration_ms,
      "sort_by" => params.sort_by,
      "sort_dir" => params.sort_dir,
      "page" => params.page
    }
  end

  # Client-facing string form of the filters just applied - blanks instead of
  # nils, so text/number inputs re-render with an empty value rather than the
  # literal word "nil".
  defp filters_for_state(params, dashboard) do
    %{
      from: params.from || "",
      to: params.to || "",
      path: params.path || "",
      ip: params.ip || "",
      method: params.method || "",
      referrer: params.referrer || "",
      min_duration_ms: blank_if_nil(params.min_duration_ms),
      max_duration_ms: blank_if_nil(params.max_duration_ms),
      sort_by: dashboard.sort_by,
      sort_dir: dashboard.sort_dir,
      page: dashboard.visit_log_page
    }
  end

  defp blank_if_nil(nil), do: ""
  defp blank_if_nil(""), do: ""
  defp blank_if_nil(value), do: to_string(value)

  # Full (re)load: replaces the visit log rows outright, as opposed to
  # action(:more_visits_loaded, ...) above, which appends to them.
  defp put_view_state(component, dashboard, filters, view) do
    component
    |> put_state(:dashboard, dashboard)
    |> put_state(:filters, filters)
    |> put_state(:bars, view.bars)
    |> put_state(:regions, view.regions)
    |> put_state(:donut_style, view.donut_style)
    |> put_state(:visit_log_rows, dashboard.visit_logs)
  end

  defp build_view(dashboard) do
    regions = build_ip_breakdown(dashboard)
    %{bars: build_bars(dashboard.top_urls), regions: regions, donut_style: donut_style(regions)}
  end

  defp build_bars([]), do: []

  defp build_bars(top_urls) do
    max_count = top_urls |> Enum.map(& &1.count) |> Enum.max()
    Enum.map(top_urls, &Map.put(&1, :pct, round(&1.count / max_count * 100)))
  end

  defp build_ip_breakdown(%{total_in_range: 0}), do: []

  defp build_ip_breakdown(%{top_ips: top_ips, total_in_range: total}) do
    top =
      top_ips
      |> Enum.zip(@donut_colors)
      |> Enum.map(fn {%{ip: ip, count: count}, color} ->
        %{label: ip, count: count, color: color}
      end)

    accounted = top |> Enum.map(& &1.count) |> Enum.sum()
    other_count = max(total - accounted, 0)

    regions =
      if other_count > 0 do
        top ++ [%{label: "Other IPs", count: other_count, color: @donut_other_color}]
      else
        top
      end

    Enum.map(regions, &Map.put(&1, :pct, Float.round(&1.count / total * 100, 1)))
  end

  defp donut_style([]), do: ""
  defp donut_style(regions), do: "background: conic-gradient(#{donut_gradient(regions)})"

  defp donut_gradient(regions) do
    {segments, _} =
      Enum.map_reduce(regions, 0.0, fn region, start ->
        stop = start + region.pct
        {"#{region.color} #{start}% #{stop}%", stop}
      end)

    Enum.join(segments, ", ")
  end

  defp format_growth(nil), do: "—"
  defp format_growth(pct) when pct > 0, do: "+#{pct}%"
  defp format_growth(pct), do: "#{pct}%"

  # Every header shows an icon, not just the active one - a column with no
  # icon at all looks like it has no sort feature, even though clicking it
  # works fine. The inactive ones get a muted neutral glyph instead.
  defp sort_icon(sort_by, _sort_dir, field) when sort_by != field, do: "⇅"
  defp sort_icon(_sort_by, "asc", _field), do: "▲"
  defp sort_icon(_sort_by, _sort_dir, _field), do: "▼"

  defp sort_icon_class(sort_by, _sort_dir, field) when sort_by != field,
    do: "opacity-30"

  defp sort_icon_class(_sort_by, _sort_dir, _field), do: "text-primary"

  defp filter_active?(value) when value in [nil, ""], do: false
  defp filter_active?(_value), do: true

  defp filters_toggle_icon(true), do: "hero-chevron-up w-4 h-4"
  defp filters_toggle_icon(false), do: "hero-chevron-down w-4 h-4"

  defp filters_toggle_label(true), do: "Hide Filters"
  defp filters_toggle_label(false), do: "Show Filters"

  # Appends a highlight ring to a filter input's base classes when it is
  # currently narrowing the results, so the admin can tell at a glance which
  # of the (now eight) filter fields are actually doing something.
  defp filter_class(base, value) do
    if filter_active?(value) do
      base <> " input-primary select-primary ring-2 ring-primary/40"
    else
      base
    end
  end

  defp active_filter_count(filters) do
    [
      filters.from,
      filters.to,
      filters.path,
      filters.ip,
      filters.method,
      filters.referrer,
      filters.min_duration_ms,
      filters.max_duration_ms
    ]
    |> Enum.count(&filter_active?/1)
  end

  # A sorted column is also a "narrowed view" the Clear button should be able
  # to reset - without this, sorting with no filter field touched leaves no
  # visible way back to the default view at all, since the button only ever
  # showed up alongside active_filter_count/1 > 0.
  defp sort_active?(filters), do: filters.sort_by != "at" or filters.sort_dir != "desc"

  defp duration_placeholder(nil, :min), do: "0"
  defp duration_placeholder(nil, :max), do: "∞"
  defp duration_placeholder(range, :min), do: to_string(range.min)
  defp duration_placeholder(range, :max), do: to_string(range.max)

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <div class="max-w-3xl mx-auto">
        <div class="flex items-center justify-center gap-2 mb-4">
          <span class="hero-user-circle w-4 h-4 text-base-content/50"></span>
          <span class="text-xs text-base-content/60">Signed in as Admin — System Portal</span>
        </div>

        <div class="flex items-center justify-center gap-3 mb-1">
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
          <h1 class="font-display text-xl sm:text-2xl text-center">
            Admin Analytics Dashboard
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-xs text-base-content/50 mb-1">
          Dashboard &gt; Portal Settings &gt; <span class="text-primary">Admin Analytics</span>
        </p>
        <p class="text-center text-sm text-base-content/60 mb-2">
          Real visitor IPs, page views, and visit logs, recorded as people browse the site.
        </p>
        <div class="flex items-center justify-center gap-1.5 mb-4 text-xs text-base-content/50">
          <span class="relative flex h-2 w-2">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75"></span>
            <span class="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
          </span>
          Live · updated {@dashboard.refreshed_at} IST
        </div>
        <div class="gold-divider w-24 mx-auto mb-6"></div>

        <script>
          {%raw}
          (function () {
            if (window.__analyticsAutoRefreshAttached) { return; }
            window.__analyticsAutoRefreshAttached = true;

            // New visits push a live update within about a second (see the
            // :visits_changed action) - this is only a fallback in case one
            // ever gets missed, so it does not need to be frequent.
            setInterval(function () {
              Hologram.dispatchAction('auto_refresh', 'page', {});
            }, 60000);
          })();
          {/raw}
        </script>

        <form $submit="apply_filters" class="card card-stock shadow-xl mb-6">
          <div class="card-body">
            <div class="flex items-center justify-between gap-2 flex-wrap">
              <button type="button" $click="toggle_filters" class="btn btn-sm btn-ghost gap-1">
                <span class={filters_toggle_icon(@filters_visible?)}></span>
                {filters_toggle_label(@filters_visible?)}
              </button>
              <div class="flex items-center gap-2">
                {%if active_filter_count(@filters) > 0 or sort_active?(@filters)}
                  {%if active_filter_count(@filters) > 0}
                    <span class="badge badge-primary badge-sm">{active_filter_count(@filters)} filter(s) active</span>
                  {%else}
                    <span class="badge badge-outline badge-sm">custom sort</span>
                  {/if}
                  <button type="button" $click="clear_filters" class="btn btn-xs btn-ghost">Clear Filters</button>
                {/if}
                <a href={@dashboard.export_url} class="btn btn-xs btn-outline">Export Visit Log To CSV</a>
              </div>
            </div>

            {%if @filters_visible?}
            <div class="flex flex-wrap items-end gap-2 mt-3">
              <div class="flex flex-col">
                <label class="text-xs text-base-content/50 mb-1" for="analytics-from">From</label>
                <input id="analytics-from" type="date" name="from" value={@filters.from} class={filter_class("input input-bordered input-sm w-36", @filters.from)} />
              </div>
              <div class="flex flex-col">
                <label class="text-xs text-base-content/50 mb-1" for="analytics-to">To</label>
                <input id="analytics-to" type="date" name="to" value={@filters.to} class={filter_class("input input-bordered input-sm w-36", @filters.to)} />
              </div>
              <div class="flex flex-col">
                <label class="text-xs text-base-content/50 mb-1" for="analytics-path">Link</label>
                <select id="analytics-path" name="path" class={filter_class("select select-bordered select-sm", @filters.path)}>
                  <option value="" selected={@filters.path == ""}>All Links</option>
                  {%for path <- @dashboard.distinct_paths}
                    <option value={path} selected={path == @filters.path}>{path}</option>
                  {/for}
                </select>
              </div>
              <div class="flex flex-col">
                <label class="text-xs text-base-content/50 mb-1" for="analytics-ip">IP</label>
                <select id="analytics-ip" name="ip" class={filter_class("select select-bordered select-sm", @filters.ip)}>
                  <option value="" selected={@filters.ip == ""}>All IPs</option>
                  {%for ip <- @dashboard.distinct_ips}
                    <option value={ip} selected={ip == @filters.ip}>{ip}</option>
                  {/for}
                </select>
              </div>
              <div class="flex flex-col">
                <label class="text-xs text-base-content/50 mb-1" for="analytics-method">Method</label>
                <select id="analytics-method" name="method" class={filter_class("select select-bordered select-sm", @filters.method)}>
                  <option value="" selected={@filters.method == ""}>All Methods</option>
                  {%for method <- @dashboard.distinct_methods}
                    <option value={method} selected={method == @filters.method}>{method}</option>
                  {/for}
                </select>
              </div>
              <div class="flex flex-col">
                <label class="text-xs text-base-content/50 mb-1" for="analytics-referrer">Source/Referrer</label>
                <select id="analytics-referrer" name="referrer" class={filter_class("select select-bordered select-sm", @filters.referrer)}>
                  <option value="" selected={@filters.referrer == ""}>All Sources</option>
                  <option value="direct" selected={@filters.referrer == "direct"}>direct</option>
                  {%for referrer <- @dashboard.distinct_referrers}
                    <option value={referrer} selected={referrer == @filters.referrer}>{referrer}</option>
                  {/for}
                </select>
              </div>
              <div class="flex flex-col">
                <label class="text-xs text-base-content/50 mb-1" for="analytics-min-duration">Min ms</label>
                <input
                  id="analytics-min-duration"
                  type="number"
                  name="min_duration_ms"
                  min="0"
                  placeholder={duration_placeholder(@dashboard.duration_range, :min)}
                  value={@filters.min_duration_ms}
                  class={filter_class("input input-bordered input-sm w-24", @filters.min_duration_ms)}
                />
              </div>
              <div class="flex flex-col">
                <label class="text-xs text-base-content/50 mb-1" for="analytics-max-duration">Max ms</label>
                {%if @dashboard.duration_range}
                  <p class="text-xs text-base-content/40 mb-1 whitespace-nowrap">
                    actual: {@dashboard.duration_range.min}–{@dashboard.duration_range.max} ms
                  </p>
                {/if}
                <input
                  id="analytics-max-duration"
                  type="number"
                  name="max_duration_ms"
                  min="0"
                  placeholder={duration_placeholder(@dashboard.duration_range, :max)}
                  value={@filters.max_duration_ms}
                  class={filter_class("input input-bordered input-sm w-24", @filters.max_duration_ms)}
                />
              </div>
              <button type="submit" class="btn btn-sm btn-primary">Apply</button>
            </div>
            {/if}
          </div>
        </form>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">Top Visited URLs ({@dashboard.range_label})</h2>
              {%if @bars == []}
                <p class="text-sm text-base-content/50 mt-3">No visits recorded in this range yet.</p>
              {%else}
                <ul class="flex flex-col gap-2 mt-3">
                  {%for bar <- @bars}
                    <li>
                      <div class="flex justify-between text-xs text-base-content/70">
                        <span class="truncate">{bar.path}</span>
                        <span class="shrink-0 ml-2">{bar.count}</span>
                      </div>
                      <div class="w-full h-2 rounded-full bg-base-content/10 mt-1 overflow-hidden">
                        <div class="h-full bg-primary rounded-full" style={"width: #{bar.pct}%"}></div>
                      </div>
                    </li>
                  {/for}
                </ul>
              {/if}
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body items-center text-center justify-center">
              <h2 class="font-display text-base uppercase tracking-wide">Total Page Views (All Time)</h2>
              <p class="font-display text-4xl text-primary mt-3">{@dashboard.total_page_views_all_time}</p>
              <p class="text-xs text-base-content/50 mt-1">Page Views · {@dashboard.total_in_range} in range</p>
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">Unique IPs Accessing</h2>
              {%if @regions == []}
                <p class="text-sm text-base-content/50 mt-3">No visits recorded in this range yet.</p>
              {%else}
                <div class="flex items-center gap-4 mt-3">
                  <div class="w-24 h-24 rounded-full shrink-0" style={@donut_style}>
                    <div class="w-full h-full rounded-full flex items-center justify-center" style="background: radial-gradient(circle, var(--color-base-100, #faf3e8) 55%, transparent 56%)">
                      <span class="font-display text-sm">{@dashboard.unique_ip_count}</span>
                    </div>
                  </div>
                  <ul class="text-xs text-base-content/70 flex flex-col gap-1">
                    {%for region <- @regions}
                      <li class="flex items-center gap-2">
                        <span class="w-2.5 h-2.5 rounded-full shrink-0" style={"background: #{region.color}"}></span>
                        {region.label} ({region.count})
                      </li>
                    {/for}
                  </ul>
                </div>
              {/if}
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">Other Info Metrics</h2>
              <div class="grid grid-cols-2 gap-3 mt-3 text-center">
                <div class="rounded-box border border-base-content/10 py-2">
                  <p class="font-display text-lg text-primary">{@dashboard.premium_activations}</p>
                  <p class="text-xs text-base-content/50">Premium Activations</p>
                </div>
                <div class="rounded-box border border-base-content/10 py-2">
                  <p class="font-display text-lg text-primary">{@dashboard.avg_duration_ms} ms</p>
                  <p class="text-xs text-base-content/50">Avg. Response Time</p>
                </div>
                <div class="rounded-box border border-base-content/10 py-2">
                  <p class="font-display text-lg text-primary">{format_growth(@dashboard.traffic_growth_pct)}</p>
                  <p class="text-xs text-base-content/50">Traffic Growth (vs prior period)</p>
                </div>
                <div class="rounded-box border border-base-content/10 py-2">
                  <p class="font-display text-lg text-primary">{@dashboard.comments_posted}</p>
                  <p class="text-xs text-base-content/50">Comments Posted</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="card card-stock shadow-xl mt-6">
          <div class="card-body overflow-x-auto">
            <h2 class="font-display text-base uppercase tracking-wide">Detailed Link Visit Logs</h2>
            {%if @visit_log_rows == []}
              <p class="text-sm text-base-content/50 mt-3">No visits recorded in this range yet.</p>
            {%else}
              <table class="table table-zebra table-sm mt-2">
                <thead>
                  <tr>
                    <th class="p-0">
                      <button type="button" $click={:sort_by_column, field: "at"} class="flex w-full items-center gap-1 px-2 py-2 cursor-pointer select-none hover:text-primary hover:bg-base-content/5">
                        <span class="hero-clock w-3.5 h-3.5"></span>
                        Date/Time (IST)
                        <span class={sort_icon_class(@filters.sort_by, @filters.sort_dir, "at")}>{sort_icon(@filters.sort_by, @filters.sort_dir, "at")}</span>
                      </button>
                    </th>
                    <th class="p-0">
                      <button type="button" $click={:sort_by_column, field: "ip"} class="flex w-full items-center gap-1 px-2 py-2 cursor-pointer select-none hover:text-primary hover:bg-base-content/5">
                        <span class="hero-globe-alt w-3.5 h-3.5"></span>
                        Visitor IP
                        <span class={sort_icon_class(@filters.sort_by, @filters.sort_dir, "ip")}>{sort_icon(@filters.sort_by, @filters.sort_dir, "ip")}</span>
                      </button>
                    </th>
                    <th class="p-0">
                      <button type="button" $click={:sort_by_column, field: "path"} class="flex w-full items-center gap-1 px-2 py-2 cursor-pointer select-none hover:text-primary hover:bg-base-content/5">
                        <span class="hero-link w-3.5 h-3.5"></span>
                        URL Visited
                        <span class={sort_icon_class(@filters.sort_by, @filters.sort_dir, "path")}>{sort_icon(@filters.sort_by, @filters.sort_dir, "path")}</span>
                      </button>
                    </th>
                    <th class="p-0">
                      <button type="button" $click={:sort_by_column, field: "referrer"} class="flex w-full items-center gap-1 px-2 py-2 cursor-pointer select-none hover:text-primary hover:bg-base-content/5">
                        <span class="hero-arrow-top-right-on-square w-3.5 h-3.5"></span>
                        Source/Referrer
                        <span class={sort_icon_class(@filters.sort_by, @filters.sort_dir, "referrer")}>{sort_icon(@filters.sort_by, @filters.sort_dir, "referrer")}</span>
                      </button>
                    </th>
                    <th class="p-0">
                      <button type="button" $click={:sort_by_column, field: "method"} class="flex w-full items-center gap-1 px-2 py-2 cursor-pointer select-none hover:text-primary hover:bg-base-content/5">
                        Method
                        <span class={sort_icon_class(@filters.sort_by, @filters.sort_dir, "method")}>{sort_icon(@filters.sort_by, @filters.sort_dir, "method")}</span>
                      </button>
                    </th>
                    <th class="p-0">
                      <button type="button" $click={:sort_by_column, field: "duration_ms"} class="flex w-full items-center gap-1 px-2 py-2 cursor-pointer select-none hover:text-primary hover:bg-base-content/5">
                        <span class="hero-bolt w-3.5 h-3.5"></span>
                        Response Time
                        <span class={sort_icon_class(@filters.sort_by, @filters.sort_dir, "duration_ms")}>{sort_icon(@filters.sort_by, @filters.sort_dir, "duration_ms")}</span>
                      </button>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {%for log <- @visit_log_rows}
                    <tr>
                      <td class="text-xs whitespace-nowrap">{log.at}</td>
                      <td class="text-xs font-mono whitespace-nowrap">{log.ip}</td>
                      <td class="text-xs max-w-[12rem] truncate">{log.path}</td>
                      <td class="text-xs whitespace-nowrap" title={log.referrer}>{log.referrer}</td>
                      <td>
                        <span class="badge badge-sm badge-outline">{log.method}</span>
                      </td>
                      <td class="text-xs whitespace-nowrap">{log.duration_ms} ms</td>
                    </tr>
                  {/for}
                </tbody>
              </table>

              <p class="text-center text-xs text-base-content/50 mt-2">
                Showing {length(@visit_log_rows)} of {@dashboard.visit_log_total} matching visit(s)
              </p>

              {%if @loading_more?}
                <p class="text-center text-xs text-base-content/50 py-2">Loading more…</p>
              {/if}
              {%if not @dashboard.visit_log_has_more? and @visit_log_rows != []}
                <p class="text-center text-xs text-base-content/40 py-2">— end of matching visits —</p>
              {/if}

              <div
                id="visit-log-sentinel"
                data-has-more={@dashboard.visit_log_has_more?}
                data-loading={@loading_more?}
                class="h-1"
              ></div>

              <script>
                {%raw}
                (function () {
                  if (window.__visitLogScrollAttached) { return; }
                  window.__visitLogScrollAttached = true;

                  // Position-only checks (sentinel near the viewport) turned out to
                  // fire on their own - not from an actual scroll, just from periodic
                  // re-renders (live push updates, auto-refresh) landing while the
                  // sentinel happened to measure as "near". A plain "scroll" listener
                  // does not reliably distinguish that from a real gesture either:
                  // built-in scroll-anchoring can fire native scroll events on its own
                  // when content reflows above the fold, with nobody touching
                  // anything. wheel/touchmove only ever originate from actual input
                  // hardware, so gating on those instead is unambiguous. Once a batch
                  // loads it stays appended for good, so a false positive here is not
                  // self-correcting - worth being strict about.
                  var userHasScrolled = false;

                  function markScrolled() {
                    userHasScrolled = true;
                  }

                  window.addEventListener("wheel", markScrolled, { passive: true });
                  window.addEventListener("touchmove", markScrolled, { passive: true });

                  setInterval(function () {
                    if (!userHasScrolled) { return; }

                    var sentinel = document.getElementById('visit-log-sentinel');
                    if (!sentinel) { return; }

                    var hasMore = sentinel.dataset.hasMore === 'true';
                    var loading = sentinel.dataset.loading === 'true';
                    if (!hasMore || loading) { return; }

                    var rect = sentinel.getBoundingClientRect();
                    var nearViewport = rect.top < window.innerHeight + 100;
                    if (nearViewport) {
                      Hologram.dispatchAction('load_more_visits', 'page', {});
                    }
                  }, 300);
                })();
                {/raw}
              </script>
            {/if}
          </div>
        </div>

        <div class="flex flex-col items-center gap-3 mt-8">
          <a href={@dashboard.export_url} class="btn btn-primary btn-block gap-2">
            <span class="hero-arrow-down-tray w-4 h-4"></span>
            Export Visit Log To CSV
          </a>
          <Link to={AdminMoviesPage} class="btn btn-outline btn-block gap-2">
            <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
            Back To Admin Portal
          </Link>
        </div>
        <p class="text-center text-xs text-base-content/50 mt-3">
          Only visits recorded since this dashboard shipped are counted — there's no data from before that.
        </p>

        <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 mt-8 text-xs text-base-content/60">
          <span class="flex items-center gap-1">
            <span class="hero-shield-check w-4 h-4 text-primary"></span>
            Secure &amp; Private
          </span>
          <span class="flex items-center gap-1">
            <span class="hero-chart-bar w-4 h-4 text-primary"></span>
            Live Portal Metrics
          </span>
          <span class="flex items-center gap-1">
            <span class="hero-link w-4 h-4 text-primary"></span>
            Custom Shareable Link
          </span>
        </div>
      </div>
    </div>
    """
  end
end
