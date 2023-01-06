defmodule Archethic.Networking.PortForwarding do
  @moduledoc """
  Manage the port forwarding
  """

  alias Archethic.Networking.IPLookup
  alias Archethic.Networking.IPLookup.NATDiscovery

  require Logger

  @doc """
  Try to open a port using the port publication from UPnP or PmP otherwise fallback to either random or manual router configuration
  """
  @spec try_open_port(port_to_open :: :inet.port_number(), force? :: boolean()) ::
          {:ok, :inet.port_number()} | :error
  def try_open_port(port, force?) when is_integer(port) and port >= 0 and is_boolean(force?) do
    Logger.info("Try to open port #{port}")

    with true <- required?(ip_lookup_provider()),
         true <- conf_overrides?() do
      do_try_open_port(port)
    else
      false ->
        Logger.info("Port forwarding is skipped")
        Logger.info("Port must be open manually")
        {:ok, port}

      :error ->
        Logger.error("Cannot publish the port #{port}")
        fallback(port, force?)
    end
  end

  defp required?(NATDiscovery), do: true
  defp required?(_), do: false

  defp conf_overrides? do
    Application.get_env(:archethic, __MODULE__, []) |> Keyword.get(:enabled, true)
  end

  defp do_try_open_port(port), do: NATDiscovery.open_port(port)

  defp fallback(port, force?, retries \\ 10)

  defp fallback(_, _force? = true, 0) do
    Logger.error(
      "Port from configuration is used but requires a manuel port forwarding setting on the router"
    )

    :error
  end

  @random_ports_range Application.compile_env!(:archethic, [__MODULE__, :port_range])
  defp fallback(port, _force? = true, retries) do
    # // If the port is not open, try to open a random port
    Logger.info("Trying to open a random port")

    case do_try_open_port(Enum.random(@random_ports_range)) do
      {:ok, port} ->
        Logger.info("Use the random port #{port} as fallback")
        {:ok, port}

      :error ->
        Logger.error("Cannot publish the a random port #{port}")

        fallback(port, _force? = true, retries - 1)
    end
  end

  defp fallback(port, _force? = false, _) do
    Logger.warning("No fallback provided for the port #{port}")

    Logger.warning(
      "Port from configuration is used but requires a manuel port forwarding setting on the router"
    )

    {:ok, port}
  end

  defp ip_lookup_provider do
    Application.get_env(:archethic, IPLookup)
  end
end
