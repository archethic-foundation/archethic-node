defmodule Archethic.Networking.IPLookup do
  @moduledoc false

  require Logger

  alias Archethic.Networking
  alias Archethic.Networking.IPLookup.RemoteDiscovery
  alias Archethic.Networking.IPLookup.NATDiscovery

  @doc """
  Get the node public ip with a fallback capability

  For example, using the NAT provider, if the UPnP discovery failed, it switches to the IPIFY to get the external public ip
  """
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, any()}
  def get_node_ip() do
    provider = provider()

    with {:ok, ip} <- provider.get_node_ip(),
         :ok <- Networking.validate_ip(ip) do
      Logger.info("Node IP discovered #{:inet.ntoa(ip)} by #{provider}")
      {:ok, ip}
    else
      {:error, reason} ->
        fallback(provider, reason)
    end
  end

  defp fallback(NATDiscovery, reason) do
    Logger.warning("Cannot use NATDiscovery: NAT IP lookup - #{inspect(reason)}")
    Logger.info("Trying PublicGateway: IPIFY as fallback")

    case RemoteDiscovery.get_node_ip() do
      {:ok, ip} ->
        {:ok, ip}

      {:error, reason} ->
        Logger.warning("Cannot use remote discovery IP lookup - #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fallback(provider, reason) do
    Logger.warning("Cannot use #{provider} IP lookup - #{inspect(reason)}")
    {:error, reason}
  end

  defp provider() do
    Application.get_env(:archethic, __MODULE__)
  end
end
