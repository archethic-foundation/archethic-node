defmodule ArchEthic.Metrics.NodeMetric do
  @moduledoc """
  Provides metrics for that paticular node
  """
  def run() do
    TelemetryMetricsPrometheus.Core.scrape()
    |> ArchEthic.Metrics.GeneraliseMetricStructure.run()
    |> ArchEthic.Metrics.MetricHelperFunctions.filter_metrics()
    |> ArchEthic.Metrics.MetricHelperFunctions.retrieve_metric_parameter_data()
    |> ArchEthic.Metrics.MetricHelperFunctions.calculate_points()
    |> ArchEthic.Metrics.MetricHelperFunctions.reduce_to_single_map()
  end
end
