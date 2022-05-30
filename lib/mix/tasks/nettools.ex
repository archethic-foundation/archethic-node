defmodule Mix.Tasks.Archethic.Nettools do
  @moduledoc """
  Provides Support for Networking tools At cli

  ## Command line options

    * `-h`, `--help`  - show this help
    * `-p`, `--punch` - Attempt to open ports
    * `-i`, `--ip`    - Public IP

  ## Command line arguments
    * `punch` - args: []-> 30002 40002, list_of ports

  ## Example

  ```sh
  mix archethic.nettools -p
  mix archethic.nettools --punch
  mix archethic.nettools -p 30_000 40_000
  mix archethic.nettools -i
  mix archethic.nettools --ip
  ```

  """
  use Mix.Task
  alias Archethic.Networking
  @http_port System.get_env("ARCHETHIC_HTTP_PORT", "40000") |> String.to_integer()
  @p2p_port System.get_env("ARCHETHIC_P2P_PORT", "30002") |> String.to_integer()

  require Logger

  @impl Mix.Task
  def run(args) do
    args
    |> parse_args
  end

  def parse_args(args) do
    OptionParser.parse(args,
      strict: [help: :boolean, punch: :boolean, ip: :boolean],
      aliases: [h: :help, p: :punch, i: :ip]
    )
    |> args_to_internal_representation()
  end

  def args_to_internal_representation({[help: true], [], []}) do
    Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
  end

  def args_to_internal_representation({[punch: true], _port_list = [port | more_ports], errors}) do
    Networking.PortForwarding.try_open_port(port |> String.to_integer(), true)
    args_to_internal_representation({[punch: true], more_ports, errors})
  end

  def args_to_internal_representation({[punch: true], _port_list = [], _errors}) do
    Networking.PortForwarding.try_open_port(@http_port, true)
    Networking.PortForwarding.try_open_port(@p2p_port, true)
  end

  def args_to_internal_representation({[ip: true], _, _}) do
    default = Application.get_env(:archethic, Networking.IPLookup)

    try do
      Application.put_env(:archethic, Networking.IPLookup, Networking.IPLookup.NATDiscovery)
      Networking.IPLookup.get_node_ip()
    after
      Application.put_env(:archethic, Networking.IPLookup, default)
    end
  end

  def args_to_internal_representation(_) do
    Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
  end
end
