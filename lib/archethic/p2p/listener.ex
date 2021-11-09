defmodule ArchEthic.P2P.Listener do
  @moduledoc false

  use GenServer

  alias ArchEthic.P2P.ListenerProtocol
  alias ArchEthic.P2P.ListenerProtocol.Supervisor, as: ListenerProtocolSupervisor

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    transport = Keyword.get(opts, :transport)
    port = Keyword.get(opts, :port)

    ranch_transport =
      case transport do
        :tcp ->
          :ranch_tcp

        _ ->
          transport
      end

    {:ok, listener_protocol_sup} = ListenerProtocolSupervisor.start_link()

    {:ok, listener_pid} =
      :ranch.start_listener(
        :archethic_p2p,
        ranch_transport,
        %{socket_opts: [{:port, port}, {:backlog, 4096}], num_acceptors: 100},
        ListenerProtocol,
        [:binary, packet: 4, active: :once]
      )

    Logger.info("P2P #{transport} Endpoint running on port #{port}")

    {:ok, %{listener_pid: listener_pid, listener_protocol_sup_pid: listener_protocol_sup}}
  end
end
