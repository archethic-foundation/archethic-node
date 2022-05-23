defmodule Archethic.Networking.IPLookup do
  @moduledoc false

  require Logger

  alias Archethic.Networking
  alias Archethic.Networking.IPLookup.PublicGateway
  alias Archethic.Networking.IPLookup.LocalDiscovery

  @doc """
  Get the node public ip with a fallback capability

  For example, using the NAT provider, if the UPnP discovery failed, it switches to the IPIFY to get the external public ip
  """
  @spec get_node_ip() :: :inet.ip_address()
  def get_node_ip() do
    provider = get_provider()

    ip =
      with {:ok, ip} <- apply(provider, :get_node_ip, []),
           :ok <- Networking.validate_ip(ip) do
        Logger.info("Node IP discovered by #{provider}")
        ip
      else
        {:error, reason} when provider == Archethic.Networking.IPLookup.NAT ->
          fallback(LocalDiscovery, reason)

        {:error, reason} ->
          fallback(provider, reason)
      end

    Logger.info("Node IP discovered: #{:inet.ntoa(ip)}")
    ip
  end

  defp fallback(LocalDiscovery, reason) do
    Logger.warning("Cannot use LocalDiscovery: NAT IP lookup - #{inspect(reason)}")
    Logger.info("Trying PublicGateway: IPIFY as fallback")

    case PublicGateway.get_node_ip() do
      {:ok, ip} ->
        ip

      {:error, reason} ->
        raise "Cannot use #{IPIFY} IP lookup - #{inspect(reason)}"
    end
  end

  defp fallback(provider, reason) do
    raise "Cannot use #{provider} IP lookup - #{inspect(reason)}"
  end

  defp get_provider do
    Application.get_env(:archethic, __MODULE__)
  end
end
