defmodule Archethic.Networking.IPLookup.RemoteDiscovery.Handler do
  @moduledoc """
  Provide abstraction over public ip provider
  """

  alias Archethic.Networking.IPLookup.Impl
  alias __MODULE__.IPIFY

  require Logger

  @behaviour Impl
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, any()}
  def get_node_ip do
    provider = module_args()

    case provider.get_node_ip() do
      {:ok, ip} ->
        {:ok, ip}

      {:error, reason} ->
        Logger.warning(
          "Cannot use the provider #{provider} for IP Lookup - reason: #{inspect(reason)}"
        )

        fallback(provider, reason)
    end
  end

  defp module_args() do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:provider, IPIFY)
  end

  defp fallback(IPIFY, reason) do
    raise "Cannot use IPIFY IP lookup - #{inspect(reason)}"
  end

  defp fallback(provider, reason) do
    raise "Cannot use #{provider} IP lookup - #{inspect(reason)}"
  end
end
