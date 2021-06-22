defmodule Uniris.Networking.IPLookup do
  @moduledoc false

  alias __MODULE__.{IPIFY, NAT, Static}

  require Logger

  @provider Application.compile_env(:uniris, __MODULE__)

  @doc """
  Get the node public ip with a fallback capability

  For example, using the NAT provider, if the UPnP discovery failed, it switches to the IPIFY to get the external public ip
  """
  @spec get_node_ip() :: :inet.ip_address()
  def get_node_ip do
    {:ok, ip} = do_get_node_ip(@provider)
    Logger.info("Node IP discovered: #{:inet.ntoa(ip)}")
    ip
  end

  defp do_get_node_ip(NAT) do
    Logger.info("Discover the ip using NAT traversal")

    case NAT.get_node_ip() do
      {:ok, ip} ->
        {:ok, ip}

      {:error, reason} ->
        Logger.warning("Cannot use NAT IP lookup - #{inspect(reason)}")
        do_get_node_ip(IPIFY)
    end
  end

  defp do_get_node_ip(IPIFY) do
    Logger.info("Discover the ip using IPFY endpoint")

    case IPIFY.get_node_ip() do
      {:ok, ip} ->
        {:ok, ip}

      {:error, reason} = e ->
        Logger.error("Cannot use IPIFY IP lookup - #{inspect(reason)}")
        e
    end
  end

  defp do_get_node_ip(Static) do
    Logger.info("Discovery the ip using the static IP")
    Static.get_node_ip()
  end
end
