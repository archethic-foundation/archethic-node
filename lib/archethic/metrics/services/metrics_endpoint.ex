defmodule ArchEthic.Metrics.Services.MetricsEndpoint do
  @moduledoc """
  This module provides a REST endpoint for metrics.
  """
  # implements MetricsEndpointbehaviour
  @behaviour ArchEthic.Metrics.Services.MetricsEndpointBehaviour

  # Constraints
  @node_port 40_000
  @node_metric_endpoint "/metrics"
  @node_metric_request_type "GET"

  # custom types
  @type ip_as_string() :: String.t()
  @type conn_ref() :: Mint.t() | any()

  @doc """
  Retreive list of ipv4 addresses , of  Active nodes
  """
  @spec retrieve_node_ip_address :: [ip_as_string()]
  def retrieve_node_ip_address() do
    Enum.map(ArchEthic.P2P.list_nodes(), fn node_details ->
      ip = :inet.ntoa(node_details.ip)
      "#{ip}"
    end)
  end

  @doc """
  Driver method for quering the @node_metric_endpoint from nodes
  """
  @spec get_metrics_from_node(ip_as_string()) :: [] | Mint.response()
  def get_metrics_from_node(ip) do
    establish_connection_to_node(ip)
  end

  @doc """
  Establishes connection at port 40_000 for given node_ip.In case of error, returns empty list.
  """
  @spec establish_connection_to_node(ip_as_string()) :: [] | Mint.response()
  def establish_connection_to_node(ip) do
    case Mint.HTTP.connect(:http, ip, @node_port) do
      {:ok, conn} -> contact_endpoint_for_data(conn)
      _ -> []
    end
  end

  @doc """
  Send get request to @node_metric_endpoint endpoint of a node.
  Returns response in case of success, otherwise returns empty list.
  """
  @spec contact_endpoint_for_data(conn_ref()) :: [] | Mint.response()
  def contact_endpoint_for_data(conn) do
    {:ok, conn, _request_ref} =
      Mint.HTTP.request(conn, @node_metric_request_type, @node_metric_endpoint, [], [])

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
