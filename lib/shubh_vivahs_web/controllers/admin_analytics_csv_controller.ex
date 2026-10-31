defmodule ShubhVivahsWeb.AdminAnalyticsCsvController do
  @moduledoc """
  Exports `AdminAnalyticsPage`'s visit log to CSV, filtered by the same
  `from`/`to`/`path`/`ip` query params the page's filter form submits. A
  plain download link rather than a Hologram page/command, since triggering
  a browser file download from inside the SPA isn't otherwise available.
  """

  use ShubhVivahsWeb, :controller

  alias ShubhVivahs.Analytics

  @header ~w(date_time_ist ip path referrer method status duration_ms)

  def export(conn, params) do
    rows =
      params
      |> Analytics.parse_filters()
      |> Analytics.export_rows()

    csv =
      [@header | Enum.map(rows, &csv_row/1)]
      |> Enum.map_join("\n", fn fields -> Enum.map_join(fields, ",", &csv_escape/1) end)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="page-visits.csv"))
    |> send_resp(200, csv)
  end

  defp csv_row(visit) do
    [
      visit.inserted_at |> Analytics.to_ist() |> NaiveDateTime.to_string(),
      visit.ip,
      visit.path,
      visit.referrer,
      visit.method,
      visit.status,
      visit.duration_ms
    ]
  end

  defp csv_escape(nil), do: ""

  defp csv_escape(value) do
    string = to_string(value)

    if String.contains?(string, [",", "\"", "\n"]) do
      ~s("#{String.replace(string, "\"", "\"\"")}")
    else
      string
    end
  end
end
