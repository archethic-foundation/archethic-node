defmodule Archethic.P2P.Listener do
  @moduledoc false

  use GenServer

  alias Archethic.P2P.ListenerProtocol

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

    {:ok, listener_pid} =
      :ranch.start_listener(
        :archethic_p2p,
        ranch_transport,
        %{socket_opts: [{:port, port}, {:backlog, 4096}], num_acceptors: 100},
        ListenerProtocol,
        [:binary, packet: 4, active: :once]
      )

    Logger.info("P2P #{transport} Endpoint running on port #{port}")

    {:ok, %{listener_pid: listener_pid}}
  end
end
