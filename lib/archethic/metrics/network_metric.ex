defmodule ArchEthic.Metrics.NetworkMetric do
  @moduledoc """
  Provides Telemetry of the network
  """
  def run() do
    ArchEthic.Metrics.MetricHelperFunctions.retrieve_node_ip_address()
    |> Task.async_stream(fn each_node_ip -> establish_connection_to_node(each_node_ip) end)
    |> ArchEthic.Metrics.MetricHelperFunctions.remove_noise()
    |> Stream.map(&ArchEthic.Metrics.GeneraliseMetricStructure.run/1)
    |> Stream.map(&ArchEthic.Metrics.MetricHelperFunctions.filter_metrics/1)
    |> Stream.map(&ArchEthic.Metrics.MetricHelperFunctions.retrieve_metric_parameter_data/1)
    |> Enum.reduce([], fn x, acc -> Enum.concat(acc, x) end)
    |> ArchEthic.Metrics.MetricHelperFunctions.aggregate_sum_n_count_n_value()
    |> ArchEthic.Metrics.MetricHelperFunctions.calculate_network_points()
    |> ArchEthic.Metrics.MetricHelperFunctions.reduce_to_single_map()
  end

  def establish_connection_to_node(ip) do
    case Mint.HTTP.connect(:http, ip, 40_000) do
      {:ok, conn} -> contact_endpoint_for_data(conn)
      _ -> []
    end
  end

  def contact_endpoint_for_data(conn) do
    {:ok, conn, _request_ref} = Mint.HTTP.request(conn, "GET", "/metrics", [], [])

    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            {:ok, _conn_close} = Mint.HTTP.close(conn)
            responses

          _unknown ->
            []
        end
    end
  end
end
