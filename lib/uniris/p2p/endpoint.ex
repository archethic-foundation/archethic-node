defmodule Uniris.P2P.Endpoint do
  @moduledoc false

  use GenServer

  alias Uniris.P2P.Endpoint.ListenerSupervisor
  alias Uniris.P2P.Transport

  require Logger

  @server_options [
    :binary,
    {:packet, 4},
    {:active, false},
    {:reuseaddr, true},
    {:backlog, 500}
  ]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    port = Keyword.fetch!(args, :port)
    transport = Keyword.fetch!(args, :transport)
    nb_acceptors = Keyword.get(args, :nb_acceptors, 10)

    {:ok, listen_socket} = Transport.listen(transport, port, @server_options)

    Logger.info("P2P #{transport} Endpoint running on port #{port}")

    {:ok, listener_sup} =
      ListenerSupervisor.start_link(Keyword.merge(args, listen_socket: listen_socket))

    {:ok,
     %{
       listen_socket: listen_socket,
       port: port,
       listener_sup: listener_sup,
       nb_acceptors: nb_acceptors,
       transport: transport
     }}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, reason},
        state = %{
          acceptor_sup: listener_sup,
          listen_socket: listen_socket,
          nb_acceptors: nb_acceptors,
          transport: transport
        }
      )
      when pid == listener_sup do
    Logger.error("Listener supervisor failed! - #{inspect(reason)}")

    {:ok, listener_sup} =
      ListenerSupervisor.start_link(
        listen_socket: listen_socket,
        transport: transport,
        nb_acceptors: nb_acceptors
      )

    {:noreply, Map.put(state, :listener_sup, listener_sup)}
  end
end
