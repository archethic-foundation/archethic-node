defmodule Archethic.P2P.ListenerProtocol do
  @moduledoc false

  alias __MODULE__.MessageProducer

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

    :gen_server.enter_loop(__MODULE__, [], %{
      socket: socket,
      transport: transport,
      ip: ip,
      port: port
    })
  end

  def handle_info(
        {_transport, socket, msg},
        state = %{transport: transport}
      ) do
    :inet.setopts(socket, active: :once)
    MessageProducer.new_message({socket, transport, msg})
    {:noreply, state}
  end

  def handle_info({_transport_closed, _socket}, state = %{ip: ip, port: port}) do
    Logger.warning("Connection closed for #{:inet.ntoa(ip)}:#{port}")
    {:stop, :normal, state}
  end
end
