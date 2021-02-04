defmodule Uniris.Networking.IPLookup.IPIFY do
  @moduledoc """
  Module provides external IP address of the node identified by IPIFY service.
  """

  alias Uniris.Networking.IPLookup.Impl

  @behaviour Impl

  @impl Impl
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :not_recognizable_ip}
  def get_node_ip do
    :inets.start()

    with {:ok, {_, _, inet_addr}} <- :httpc.request('http://api.ipify.org'),
         {:ok, ip} <- :inet.parse_address(inet_addr) do
      :inets.stop()
      {:ok, ip}
    else
      {:error, {:failed_connect, _reason}} ->
        :inets.stop()
        {:error, :not_recognizable_ip}

      {:error, :einval} ->
        :inets.stop()
        {:error, :not_recognizable_ip}
    end
  end
end
