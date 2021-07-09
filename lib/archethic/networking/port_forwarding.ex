defmodule ArchEthic.Networking.PortForwarding do
  @moduledoc """
  Manage the port forwarding
  """

  alias ArchEthic.Networking.IPLookup
  alias ArchEthic.Networking.IPLookup.NAT

  require Logger

  @doc """
  Try to open a port using the port publication from UPnP or PmP otherwise fallback to either random or manual router configuration
  """
  @spec try_open_port(port_to_open :: :inet.port_number(), force? :: boolean()) ::
          :inet.port_number()
  def try_open_port(port, force?) when is_integer(port) and port >= 0 and is_boolean(force?) do
    Logger.info("Try to open port #{port}")

    with true <- required?(ip_lookup_provider()),
         true <- conf_overrides?(),
         {:ok, port} <- do_try_open_port(port) do
      port
    else
      false ->
        Logger.info("Port forwarding is skipped")
        Logger.info("Port must be open manually")
        port

      {:error, _} ->
        Logger.error("Cannot publish the port #{port}")
        fallback(port, force?)
    end
  end

  defp required?(NAT), do: true
  defp required?(_), do: false

  defp conf_overrides? do
    Application.get_env(:archethic, __MODULE__, []) |> Keyword.get(:enabled, true)
  end

  defp do_try_open_port(port), do: assign_port([:natupnp_v1, :natupnp_v2, :natpmp], port)

  defp assign_port([], _), do: {:error, :port_unassigned}

  defp assign_port([protocol_module | protocol_modules], port) do
    with {:ok, router_ip} <- protocol_module.discover(),
         {:ok, _, internal_port, _, _} <-
           protocol_module.add_port_mapping(router_ip, :tcp, port, port, 0) do
      {:ok, internal_port}
    else
      {:error, _} -> assign_port(protocol_modules, port)
    end
  end

  defp fallback(port, _force? = true) do
    case do_try_open_port(0) do
      {:ok, port} ->
        Logger.info("Use the random port #{port} as fallback")
        port

      {:error, _} ->
        Logger.error("Cannot publish the a random port #{port}")

        raise "Port from configuration is used but requires a manuel port forwarding setting on the router"
    end
  end

  defp fallback(port, _force? = false) do
    Logger.error("No fallback provided for the port #{port}")

    Logger.info(
      "Port from configuration is used but requires a manuel port forwarding setting on the router"
    )

    port
  end

  defp ip_lookup_provider do
    Application.get_env(:archethic, IPLookup)
  end
end
