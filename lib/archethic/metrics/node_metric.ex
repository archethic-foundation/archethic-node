defmodule ArchEthic.Metrics.NodeMetric do
  @moduledoc """
  Abstraction and Execution of several methods to Poll this-Node
  """
  def run() do
    TelemetryMetricsPrometheus.Core.scrape()
    |> ArchEthic.Metrics.Parser.run()
    |> ArchEthic.Metrics.Helpers.filter_metrics()
    |> ArchEthic.Metrics.Helpers.retrieve_metric_parameter_data()
    |> ArchEthic.Metrics.Helpers.calculate_points()
    |> ArchEthic.Metrics.Helpers.reduce_to_single_map()
  end
end
