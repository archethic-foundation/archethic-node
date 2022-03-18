defmodule ArchEthic.Metrics.Collector do
  @moduledoc """
  Handle the flow of metrics collection
  """

  alias ArchEthic.Metrics.Aggregator
  alias ArchEthic.Metrics.Parser
  alias ArchEthic.P2P

  @callback fetch_metrics(:inet.ip_address()) :: {:ok, String.t()} | {:error, any()}

  @doc """
  Get the list of Node IP addresses
  """
  @spec retrieve_node_ip_addresses_and_http_ports() :: list({:inet.ip_address(), port()})
  def retrieve_node_ip_addresses_and_http_ports do
    Enum.map(P2P.authorized_nodes(), &{&1.ip, &1.http_port})
  end

  @doc """
  Responsible for retrieving network metrics.
  """
  @spec retrieve_network_metrics(list({:inet.ip_address(), port()})) :: map()
  def retrieve_network_metrics(node_ip_addresses_with_http_port) do
    Task.async_stream(node_ip_addresses_with_http_port, &service().fetch_metrics(&1))
    |> Stream.filter(&match?({:ok, {:ok, _}}, &1))
    |> Stream.map(fn {:ok, {:ok, result}} -> result end)
    |> Stream.map(&Parser.extract_from_string/1)
    |> Stream.map(&filter_metrics/1)
    |> Stream.map(&Parser.reduce_metrics/1)
    |> Enum.flat_map(& &1)
    |> Aggregator.inject_tps()
    |> Aggregator.reduce_values()
    |> Aggregator.summarize()
    |> reduce_to_single_map()
  end

  defp service do
    Application.get_env(
      :archethic,
      __MODULE__,
      __MODULE__.MetricsEndpoint
    )
  end

  defp filter_metrics(metrics) do
    Enum.filter(metrics, fn %{name: name} -> accept_metric?(name) end)
  end

  defp accept_metric?("archethic_mining_proof_of_work_duration"), do: true
  defp accept_metric?("archethic_mining_full_transaction_validation_duration"), do: true
  defp accept_metric?("archethic_p2p_send_message_duration"), do: true
  defp accept_metric?(_), do: false

  defp reduce_to_single_map(data_list_of_maps) do
    Enum.reduce(data_list_of_maps, fn a, b ->
      Map.merge(a, b, fn _key, a1, a2 ->
        a1 + a2
      end)
    end)
  end
end
