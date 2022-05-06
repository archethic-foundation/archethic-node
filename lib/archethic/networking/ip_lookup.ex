defmodule Archethic.Networking.IPLookup do
  @moduledoc false

  alias __MODULE__.IPIFY
  alias __MODULE__.NAT

  require Logger

  @doc """
  Get the node public ip with a fallback capability

  For example, using the NAT provider, if the UPnP discovery failed, it switches to the IPIFY to get the external public ip
  """
  @spec get_node_ip() :: :inet.ip_address()
  def get_node_ip do
    provider = get_provider()

    ip =
      case apply(provider, :get_node_ip, []) do
        {:ok, ip} ->
          Logger.info("Node IP discovered by #{provider}")
          ip

        {:error, reason} ->
          fallback(provider, reason)
      end

    Logger.info("Node IP discovered: #{:inet.ntoa(ip)}")
    ip
  end

  defp get_provider do
    Application.get_env(:archethic, __MODULE__)
  end

  defp fallback(NAT, reason) do
    Logger.warning("Cannot use NAT IP lookup - #{inspect(reason)}")
    Logger.info("Trying IPFY as fallback")

    case IPIFY.get_node_ip() do
      {:ok, ip} ->
        ip

      {:error, reason} ->
        fallback(IPIFY, reason)
    end
  end

  defp fallback(provider, reason) do
    raise "Cannot use #{provider} IP lookup - #{inspect(reason)}"
  end
end
