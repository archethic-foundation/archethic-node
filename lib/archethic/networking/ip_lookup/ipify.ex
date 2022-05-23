defmodule Archethic.Networking.IPLookup.IPIFY do
  @moduledoc """
  Module provides external IP address of the node identified by IPIFY service.
  """

  alias Archethic.Networking.IPLookup.PublicGateway

  @behaviour PublicGateway

  @impl PublicGateway
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :not_recognizable_ip}
  def get_node_ip() do
    with {:ok, {_, _, inet_addr}} <- :httpc.request('http://api.ipify.org'),
         {:ok, ip} <- :inet.parse_address(inet_addr) do
      {:ok, ip}
    else
      {:error, {:failed_connect, _reason}} ->
        {:error, :not_recognizable_ip}

      {:error, :einval} ->
        :inets.stop()
        {:error, :not_recognizable_ip}
    end
  end
end
