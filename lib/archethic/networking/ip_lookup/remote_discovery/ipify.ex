defmodule Archethic.Networking.IPLookup.RemoteDiscovery.IPIFY do
  @moduledoc """
  Module provides external IP address of the node identified by IPIFY service.
  """

  alias Archethic.Networking.IPLookup.Impl

  @behaviour Impl

  @impl Impl
  @spec get_node_ip() ::
          {:ok, :inet.ip_address()} | {:error, :not_recognizable_ip} | {:error, any()}
  def get_node_ip() do
    with {:ok, {_, _, inet_addr}} <- :httpc.request('http://api.ipify.org'),
         {:ok, ip} <- :inet.parse_address(inet_addr) do
      {:ok, ip}
    else
      {:error, {:failed_connect, _reason}} ->
        {:error, :not_recognizable_ip}

      {:error, :einval} ->
        {:error, :not_recognizable_ip}

      {:error, _} = e ->
        e
    end
  end
end
