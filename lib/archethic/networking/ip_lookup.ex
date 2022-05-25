defmodule Archethic.Networking.IPLookup do
  @moduledoc false

  require Logger

  alias Archethic.Networking
  alias Archethic.Networking.IPLookup.RemoteDiscovery
  alias Archethic.Networking.IPLookup.LocalDiscovery

  @doc """
  Get the node public ip with a fallback capability

  For example, using the NAT provider, if the UPnP discovery failed, it switches to the IPIFY to get the external public ip
  """
  @spec get_node_ip() :: :inet.ip_address()
  def get_node_ip() do
    provider = module_args()

    ip =
      with {:ok, ip} <- provider.get_node_ip(),
           :ok <- Networking.validate_ip(ip) do
        Logger.info("Node IP discovered by #{provider}")
        ip
      else
        {:error, reason} ->
          fallback(provider, reason)
      end

    Logger.info("Node IP discovered: #{:inet.ntoa(ip)}")
    ip
  end

  defp fallback(LocalDiscovery, reason) do
    Logger.warning("Cannot use LocalDiscovery: NAT IP lookup - #{inspect(reason)}")
    Logger.info("Trying PublicGateway: IPIFY as fallback")

    case RemoteDiscovery.get_node_ip() do
      {:ok, ip} ->
        ip

      {:error, reason} ->
        fallback(RemoteDiscovery, reason)
    end
  end

  defp fallback(provider, reason) do
    raise "Cannot use #{provider} IP lookup - #{inspect(reason)}"
  end

  defp module_args() do
    Application.get_env(:archethic, __MODULE__)
  end
end
