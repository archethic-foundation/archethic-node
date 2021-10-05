defmodule ArchEthicWeb.MetricsController do
  alias TelemetryMetricsPrometheus.Core
  use ArchEthicWeb, :controller

  def index(conn, _params) do
    metrics = Core.scrape()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  def parse(content) do
    [_, metric_name, labels, value] = Regex.run(~r/(.*){(.*)}(.*)/, content)

    labels_data =
      labels
      |> remove_quotes(~r/"/)
      |> String.split(",")
      |> Enum.reduce(%{}, fn match, acc ->
        [key, val] = String.split(match, "=")
        Map.put(acc, key, val)
      end)

    bucket_map = Map.merge(labels_data, %{"value" => value})
    Map.put_new(%{}, metric_name, bucket_map)
  end

  def parse_other(content) do
    [_, metric_name, value] = Regex.run(~r/(.*\s)(.*)/, content)
    Map.put_new(%{}, metric_name, %{"value" => value})
  end

  def remove_quotes(str, regex, replacement \\ "") do
    Regex.replace(regex, str, replacement)
  end
end
