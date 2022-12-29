defmodule Archethic.Networking.IPLookup.NATDiscovery.MiniUPNP do
  @moduledoc false

  require Logger

  @upnpc Application.app_dir(:archethic, "priv/c_dist/upnpc")

  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, any()}
  def get_node_ip do
    case System.cmd(@upnpc, ["-s"]) do
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
    case System.cmd(@upnpc, ["-s"]) do
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
  defp do_open_port(local_ip, port) do
    with {reason, status} when status != 0 <- System.cmd(@upnpc, map_query(local_ip, port)),
         {:error, e} <- parse_reason(reason),
         :ok <- handle_error(e, local_ip, port),
         {_, 0} <- System.cmd(@upnpc, map_query(local_ip, port)) do
      :ok
    else
      {_, 0} ->
        :ok

      {reason, _status} ->
        Logger.debug(reason)
        :error

      :error ->
        Logger.debug("Unkonwn error", port: port)
        :error
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

  @spec parse_reason(String.t()) ::
          {:error, :conflict_in_mapping_entry | :unknown}
  defp parse_reason(reason) do
    # upon more condtions , refactor with cond do end
    if Regex.scan(~r/ConflictInMappingEntry/, reason, capture: :all) != [] do
      Logger.warning("Port is employed to another host.")
      {:error, :conflict_in_mapping_entry}
    else
      {:error, :unknown}
    end
  end

  @spec handle_error(:conflict_in_mapping_entry | :unknown, :inet.ip_address(), non_neg_integer()) ::
          :ok | :error
  defp handle_error(:conflict_in_mapping_entry, _, port) do
    case System.cmd(@upnpc, revoke_query(port)) do
      {_, 0} -> :ok
      _ -> :error
    end
  end

  defp handle_error(:unknown, _, _), do: :error

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
