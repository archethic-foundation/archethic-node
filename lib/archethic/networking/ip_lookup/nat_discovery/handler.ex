defmodule Archethic.Networking.IPLookup.NATDiscovery.Handler do
  @moduledoc """
  Provide abstraction over :natupnp_v1, :natupnp_v2, :natpmp
  """

  alias Archethic.Networking.IPLookup.Impl

  alias __MODULE__.UPnPv1
  alias __MODULE__.UPnPv2
  alias __MODULE__.PMP

  require Logger

  @behaviour Impl
  def get_node_ip() do
    provider = module_args()
    do_get_node_ip(provider)
  end

  defp do_get_node_ip(provider) do
    case provider.get_node_ip() do
      {:ok, ip} ->
        {:ok, ip}

      {:error, reason} ->
        Logger.error(
          "Cannot use the provider #{provider} for IP Lookup - reason: #{inspect(reason)}"
        )

        fallback({provider}, reason)
    end
  end

  defp fallback({UPnPv1}, _reason) do
    do_get_node_ip(UPnPv2)
  end

  defp fallback({UPnPv2}, _reason) do
    do_get_node_ip(PMP)
  end

  defp fallback({PMP}, reason) do
    {:error, reason}
  end

  defp fallback({_provider}, reason) do
    {:error, reason}
  end

  defp module_args() do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:provider, UPnPv1)
  end
end
