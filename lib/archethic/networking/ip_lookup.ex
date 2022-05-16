defmodule Archethic.Networking.IPLookup do
  @moduledoc false

  alias Archethic.Networking

  require Logger

  @doc """
  Get the node public ip with a fallback capability

  For example, using the NAT provider, if the UPnP discovery failed, it switches to the IPIFY to get the external public ip
  """
  @spec get_node_ip() :: :inet.ip_address()
  def get_node_ip do
    provider = get_provider()

    ip =
      with {:ok, ip} <- apply(provider, :get_node_ip, []),
           :ok <- Networking.validate_ip(ip) do
        Logger.info("Node IP discovered by #{provider}")
        ip
      else
        {:error, reason} when reason == :invalid_ip ->
          fallback_nat(reason)

        {:error, reason} ->
          fallback(provider, reason)
      end

    Logger.info("Node IP discovered: #{:inet.ntoa(ip)}")
    ip
  end

  defp fallback_nat(reason) do
    Logger.warning("Cannot use NAT IP lookup - #{inspect(reason)}")
    Logger.info("Trying IPFY as fallback")
    ipify_provider = get_ipify_provider()

    case ipify_provider.get_node_ip() do
      {:ok, ip} ->
        ip

      {:error, reason} ->
        fallback(ipify_provider, reason)
    end
  end

  defp fallback(provider, reason) do
    raise "Cannot use #{provider} IP lookup - #{inspect(reason)}"
  end

  defp get_provider() do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:provider)
  end

  defp get_ipify_provider() do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:ipify_provider, IPIFFY)
  end
end
