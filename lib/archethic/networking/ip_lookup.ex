defmodule Archethic.Networking.IPLookup do
  @moduledoc false

  alias __MODULE__.IPIFY
  alias __MODULE__.NAT
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
           :ok <- validate_ip(ip, should_validate_node_ip?()) do
        Logger.info("Node IP discovered by #{provider}")
        ip
      else
        {:error, reason} ->
          fallback(provider, reason)
      end

    Logger.info("Node IP discovered: #{:inet.ntoa(ip)}")
    ip
  end

  def should_validate_node_ip?() do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:validate_node_ip, true)
  end

  defp validate_ip(ip, true) do
    if Networking.valid_ip?(ip) do
      :ok
    else
      {:error, :invalid_ip}
    end
  end

  defp validate_ip(_ip, false), do: :ok

  defp get_provider do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:provider)
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
