defmodule ArchethicWeb.Explorer.MetricsController do
  alias TelemetryMetricsPrometheus.Core
  use ArchethicWeb.Explorer, :controller

  def index(conn, _params) do
    metrics = Core.scrape()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end
end
