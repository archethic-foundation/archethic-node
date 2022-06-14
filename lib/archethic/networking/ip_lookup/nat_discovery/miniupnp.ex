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

  @spec open_port(non_neg_integer()) :: :ok | :error
  def open_port(port) do
    # {:ok, [{local_ip, _, _} | _]} = :inet.getif()

    local_ip =
      case System.cmd(@upnpc, ["-s"]) do
        {output, 0} ->
          [[_, ip]] = Regex.scan(~r/Local LAN ip address : ([0-9.]*)/, output, capture: :all)

          ip
          |> to_charlist()
          |> :inet.parse_address()
          |> elem(1)

        {_, status} ->
          {:error, status}
      end

    opts = [
      # Add redirection
      "-a",
      # Local ip
      local_ip |> :inet.ntoa() |> to_string(),
      # Local opened port
      "#{port}",
      # Remote port to open
      "#{port}",
      # Protocol
      "tcp",
      # Lifetime
      "0"
    ]

    case System.cmd(@upnpc, opts) do
      {_, 0} ->
        {:ok, port}

      {reason, _status} ->
        Logger.debug(reason)
        :error
    end
  end
end
