defmodule Mix.Tasks.Archethic.Nettools do
  @moduledoc """
  Provides Support for Networking tools At cli

  ## Command line options

    * `-h`, `--help`  - show this help
    * `-p`, `--punch` - Attempt to open ports
    * `-i`, `--ip`    - Public IP
    * `-n`, `--nat`   - NATDiscovery

  ## Command line arguments
    * `punch` - args: []-> 30002,40002, list_of ports
    * `nat`   - args: []-> upnp_v1,upnp_v2,pmp, single protocol

  ## Example

  ```sh
  mix archethic.nettools -p
  mix archethic.nettools --punch
  mix archethic.nettools -p 30000 40000
  mix archethic.nettools -i
  mix archethic.nettools --ip
  mix archethic.nettools -n
  mix archethic.nettools --nat
  mix archethic.nettools -n pmp

  ```

  """
  use Mix.Task
  alias Archethic.Networking

  require Logger

  @impl Mix.Task
  def run(args) do
    args
    |> parse_args
  end

  def parse_args(args) do
    IO.inspect(args)

    OptionParser.parse(args,
      strict: [help: :boolean, punch: :boolean, ip: :boolean, nat: :boolean],
      aliases: [h: :help, p: :punch, i: :ip, n: :nat]
    )
    |> IO.inspect()
    |> args_to_internal_representation()
  end

  def args_to_internal_representation({[help: true], [], []}) do
    Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
  end

  def args_to_internal_representation({[punch: true], _port_list = [port | more_ports], errors}) do
    Networking.PortForwarding.try_open_port(abs(Integer.parse(port) |> elem(0)), true)
    args_to_internal_representation({[punch: true], more_ports, errors})
  end

  def args_to_internal_representation({[punch: true], _port_list = [], _errors}) do
    Networking.PortForwarding.try_open_port(40000, true)
    Networking.PortForwarding.try_open_port(30002, true)
  end

  def args_to_internal_representation({[ip: true], _, _}) do
    {_, ip} = Networking.IPLookup.RemoteDiscovery.get_node_ip()
    Logger.info("Public ip: #{:inet.ntoa(ip)}")
  end

  def args_to_internal_representation({[nat: true], [], _}) do
    Networking.IPLookup.NATDiscovery.get_node_ip()
  end

  def args_to_internal_representation({[nat: true], [protocol], _}) do
    case protocol |> String.downcase() do
      val when val in ["upnp_v1", "upnpv1", "v1"] ->
        msg = Networking.IPLookup.NATDiscovery.UPnPv1.get_node_ip()
        Logger.info("#{inspect(msg)}")

      val when val in ["upnp_v2", "upnpv2", "v2"] ->
        msg = Networking.IPLookup.NATDiscovery.UPnPv2.get_node_ip()
        Logger.info("#{inspect(msg)}")

      val when val in ["pmp"] ->
        msg = Networking.IPLookup.NATDiscovery.PMP.get_node_ip()
        Logger.info("#{inspect(msg)}")
    end
  end

  def args_to_internal_representation(_) do
    Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
  end
end
