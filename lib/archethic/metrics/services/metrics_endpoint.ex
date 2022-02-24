defmodule ArchEthic.Metrics.Services.MetricsEndpoint do

  @behaviour ArchEthic.Metrics.Services.MetricsEndpointBehaviour


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
    case Mint.HTTP.connect(:http, ip, 40_000) do
      {:ok, conn} -> contact_endpoint(conn)
      _ -> []
    end
  end

  @doc """
  Send get request to /metrics endpoint of a node.
  Returns response in case of success, otherwise returns empty list.
  """
  def contact_endpoint(conn) do
    {:ok, conn, _request_ref} = Mint.HTTP.request(conn, "GET", "/metrics", [], [])

    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            {:ok, _conn_close} =   Mint.HTTP.close(conn)
            IO.inspect responses
            responses

          _unknown ->
            []
        end
    end
  end
end
