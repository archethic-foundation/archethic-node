defmodule Archethic.P2P.Listener do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.P2P.ListenerProtocol

  alias Archethic.PubSub

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    transport = Keyword.get(opts, :transport)
    port = Keyword.get(opts, :port)
    PubSub.register_to_node_status()

    # test(transport, port)
    {:ok, %{transport: transport, port: port}}
  end

  def handle_info(:node_up, %{transport: transport, port: port}) do
    ranch_transport =
      case transport do
        :tcp ->
          :ranch_tcp

        _ ->
          transport
      end

    case :ranch.start_listener(
           :archethic_p2p,
           ranch_transport,
           %{socket_opts: [{:port, port}, {:backlog, 4096}], num_acceptors: 100},
           ListenerProtocol,
           [:binary, packet: 4, active: :once, keepalive: true, reuseaddr: true]
         ) do
      {:ok, listener_pid} ->
        Logger.info("P2P #{transport} Endpoint running on port #{port}")

        {:noreply, %{listener_pid: listener_pid, port: port, transport: transport}}

      {:error, :eaddrinuse} ->
        Logger.error(
          "P2P #{transport} Endpoint cannot listen on port #{port}. Port already in use"
        )

        System.stop(1)
    end
  end

  def handle_info(:node_down, %{
        transport: transport,
        port: port,
        listener_pid: _
      }) do
    :ranch.stop_listener(:archethic_p2p)

    {:noreply, %{transport: transport, port: port}, :hibernate}
  end

  def handle_info(:node_down, state) do
    {:noreply, state, :hibernate}
  end
end
