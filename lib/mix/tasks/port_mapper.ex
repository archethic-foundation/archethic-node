defmodule Mix.Tasks.Archethic.PortMapper do
  use Mix.Task
  alias Archethic.Networking
  @impl Mix.Task
  def run(args) do
    args
    |> parse_args
  end

  def parse_args(args) do
    OptionParser.parse(args,
      switches: [help: :boolean, punch: :boolean, ip_address: :boolean, nat: true],
      aliases: [h: :help, p: :punch, pip: :ip_address]
    )
    |> args_to_internal_representation()
  end

  def args_to_internal_representation({[help: true], [], []}) do
    Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
  end

  def args_to_internal_representation({[punch: true], _port_list = [], _errors}) do
    Networking.PortForwarding.try_open_port(40000, true)
    Networking.PortForwarding.try_open_port(30002, true)
  end

  def args_to_internal_representation({[punch: true], _port_list = [port | more_ports], errors})
      when is_number(port) do
    Networking.PortForwarding.try_open_port(port, true)
    args_to_internal_representation({[punch: true], more_ports, errors})
  end

  def args_to_internal_representation({[ip_address: true], _, _}) do
    Networking.IPLookup.RemoteDiscovery.IPIFY.get_node_ip()
  end

  def args_to_internal_representation({[nat: true], [protocol], _}) do
    case protocol do
      val when val in ["upnp_v1", "upnpv1", "v1"] ->
        Networking.IPLookup.NATDiscovery.UPnPv1.get_node_ip()

      val when val in ["upnp_v2", "upnpv2", "v2"] ->
        Networking.IPLookup.NATDiscovery.UPnPv2.get_node_ip()

      val when val in ["pmp"] ->
        Networking.IPLookup.NATDiscovery.PMP.get_node_ip()

      _ ->
        Networking.IPLookup.NATDiscovery.get_node_ip()
    end
  end

  def args_to_internal_representation(_) do
    Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
  end
end
