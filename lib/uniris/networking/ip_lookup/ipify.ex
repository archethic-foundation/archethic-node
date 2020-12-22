
defmodule Uniris.Networking.IPLookup.Ipify do
  @moduledoc """
  Module provides external IP address of the node identified by IPIFY service.
  """

  @error_invalid_ip "Invalid IP address"

  # Public
  
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, binary}
  def get_node_ip do
    with {:ok, {_, _, inet_addr}} <- :httpc.request('http://api.ipify.org'),
    {:ok, ip} <- :inet.parse_address(inet_addr) do
      :inets.stop()

      {:ok, ip}
    else
      {:error, :einval} -> {:error, @error_invalid_ip}
      {:error, reason} -> {:error, reason}
    end
  end
end