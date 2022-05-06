defmodule Archethic.P2P.ListenerProtocol do
  @moduledoc false

  alias __MODULE__.BroadwayPipeline
  alias __MODULE__.MessageProducer
  alias __MODULE__.MessageProducerRegistry

  require Logger

  @behaviour :ranch_protocol

  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [{ref, transport, opts}])
    {:ok, pid}
  end

  def init({ref, transport, opts}) do
    {:ok, socket} = :ranch.handshake(ref)
    :ok = transport.setopts(socket, opts)

    {:ok, {ip, port}} = :inet.peername(socket)

    {:ok, _pid} =
      BroadwayPipeline.start_link(
        socket: socket,
        transport: transport,
        conn_pid: self(),
        ip: ip,
        port: port
      )

    Process.sleep(100)

    [{producer_pid, _}] = Registry.lookup(MessageProducerRegistry, socket)

    :gen_server.enter_loop(__MODULE__, [], %{
      socket: socket,
      transport: transport,
      producer_pid: producer_pid,
      ip: ip,
      port: port
    })
  end

  def handle_info(
        {_transport, socket, msg},
        state = %{producer_pid: producer_pid}
      ) do
    :inet.setopts(socket, active: :once)
    MessageProducer.new_message(producer_pid, msg)
    {:noreply, state}
  end

  def handle_info({_transport_closed, _socket}, state = %{ip: ip, port: port}) do
    Logger.warning("Connection closed for #{:inet.ntoa(ip)}:#{port}")
    {:stop, :normal, state}
  end
end
