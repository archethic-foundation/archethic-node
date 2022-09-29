defmodule Archethic.Metrics.Collector.MetricsEndpoint do
  @moduledoc """
  This module provides a REST endpoint for metrics.
  """

  alias Archethic.Metrics.Collector

  @behaviour Collector

  @node_metric_endpoint_uri "/metrics"
  @node_metric_request_type "GET"

  @impl Collector
  def fetch_metrics(ip_address, http_port) do
    with {:ok, conn_ref} <- establish_connection(ip_address, http_port),
         {:ok, conn, _req_ref} <- request(conn_ref),
         {:ok, data} <- stream_response(conn) do
      {:ok, :erlang.list_to_binary(data)}
    end
  end

  defp establish_connection(ip, http_port) do
    Mint.HTTP.connect(:http, ip |> :inet.ntoa() |> to_string(), http_port)
  end

  defp request(conn_ref) do
    Mint.HTTP.request(
      conn_ref,
      @node_metric_request_type,
      @node_metric_endpoint_uri,
      [],
      []
    )
  end

  defp stream_response(conn, acc \\ []) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, _, [{:status, _, 200}, {:headers, _, _}, {:data, _, data}, {:done, _}]} ->
            {:ok, [data]}

          {:ok, conn, [{:status, _, 200}, {:headers, _, _}, {:data, _, data}]} ->
            stream_response(conn, [data | acc])

          {:ok, conn, [{:data, _, data}]} ->
            stream_response(conn, [data | acc])

          {:ok, _, [{:data, _, data}, {:done, _}]} ->
            {:ok, [data | acc] |> Enum.reverse()}

          _ ->
            :error
        end
    after
      5_000 ->
        {:error, :timeout}
    end
  end
end
