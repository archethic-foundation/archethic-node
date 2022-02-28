defmodule ArchEthic.Metrics.Services.MetricsEndpoint do
  @moduledoc """
  This module provides a REST endpoint for metrics.
  """

  @behaviour ArchEthic.Metrics.Services.MetricsEndpointBehaviour

  @node_contact_port 40_000
  @node_metric_endpoint_uri "/metrics"
  @node_metric_request_type "GET"

  def retrieve_node_ip_address() do
    Enum.map(ArchEthic.P2P.list_nodes(), fn node_details ->
      ip = :inet.ntoa(node_details.ip)
      "#{ip}"
    end)
  end

  @doc """
  Establishes connection at port 40_000 for given node_ip.In case of error, returns empty list.
  """
  def establish_connection(ip) do
    case Mint.HTTP.connect(:http, ip, @node_contact_port) do
      {:ok, conn_ref} -> conn_ref
      _ -> []
    end
  end

  @doc """
  Send get request to /metrics endpoint of a node.
  Returns response in case of success, otherwise returns empty list.
  """
  def contact_endpoint(conn_ref) do
    case conn_ref do
      [] -> []
      _ -> request_and_wait_for_response(conn_ref)
    end
  end

  @spec request_and_wait_for_response(Mint.HTTP.t()) :: [
          {:done, reference}
          | {:pong, reference}
          | {:data, reference, binary}
          | {:error, reference, any}
          | {:headers, reference, [{any, any}]}
          | {:status, reference, non_neg_integer}
          | {:push_promise, reference, reference, [{any, any}]}
        ]
  def request_and_wait_for_response(conn_ref) do
    conn =
      case Mint.HTTP.request(
             conn_ref,
             @node_metric_request_type,
             @node_metric_endpoint_uri,
             [],
             []
           ) do
        {:ok, conn, _request_ref} -> conn
        _ -> []
      end

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
