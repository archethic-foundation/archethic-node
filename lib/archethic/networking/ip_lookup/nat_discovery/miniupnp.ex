defmodule Archethic.Networking.IPLookup.NATDiscovery.MiniUPNP do
  @moduledoc false

  require Logger

  def upnpc() do
    Application.app_dir(:archethic, "priv/c_dist/upnpc")
  end

  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, any()}
  def get_node_ip do
    case System.cmd(upnpc(), ["-s"]) do
      {output, 0} ->
        [[_, ip]] = Regex.scan(~r/ExternalIPAddress = ([0-9.]*)/, output, capture: :all)

        ip
        |> to_charlist()
        |> :inet.parse_address()

      {_, status} ->
        {:error, status}
    end
  end

  @spec open_port(non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  def open_port(port) do
    with {:ok, local_ip} <- get_local_ip(),
         :ok <- do_open_port(local_ip, port) do
      {:ok, port}
    end
  end

  defp get_local_ip do
    case System.cmd(upnpc(), ["-s"]) do
      {output, 0} ->
        [[_, ip]] = Regex.scan(~r/Local LAN ip address : ([0-9.]*)/, output, capture: :all)

        ip
        |> to_charlist()
        |> :inet.parse_address()

      {_, status} ->
        Logger.error("Cannot get local ip from miniupnp - status: #{status}")
        :error
    end
  end

  @spec do_open_port(:inet.ip_address(), non_neg_integer()) :: :ok | :error
  defp do_open_port(local_ip, port, retries \\ 2)

  defp do_open_port(_local_ip, _port, 0), do: :error

  defp do_open_port(local_ip, port, retries) do
    case System.cmd(upnpc(), map_query(local_ip, port)) do
      {_, 0} ->
        :ok

      {reason, _} ->
        handle_error(reason, local_ip, port)

        do_open_port(local_ip, port, retries - 1)
    end
  end

  @protocol "tcp"
  @spec map_query(:inet.ip_address(), non_neg_integer()) :: [String.t()]
  defp map_query(local_ip, port) do
    [
      # Add redirection
      "-a",
      # Local ip
      local_ip |> :inet.ntoa() |> to_string(),
      # Local opened port
      "#{port}",
      # Remote port to open
      "#{port}",
      # Protocol
      @protocol,
      # Lifetime
      "0"
    ]
  end

  @spec handle_error(
          reason :: String.t(),
          local_ip :: :inet.ip_address(),
          port :: non_neg_integer()
        ) :: :error | any()
  defp handle_error(reason, _local_ip, port) do
    if Regex.scan(~r/ConflictInMappingEntry/, reason, capture: :all) != [] do
      Logger.warning("Port is employed to another host.")
      System.cmd(upnpc(), revoke_query(port))
    end
  end

  @spec revoke_query(non_neg_integer()) :: [String.t()]
  defp revoke_query(port) do
    [
      # deleting redirection
      "-d",
      # external port to delete
      "#{port}",
      # Protocol
      @protocol
    ]
  end
end
