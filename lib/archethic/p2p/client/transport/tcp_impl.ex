defmodule Archethic.P2P.Client.Transport.TCPImpl do
  @moduledoc false

  alias Archethic.P2P.Client.Transport

  @options [
    :binary,
    packet: 4,
    active: :once,
    keepalive: true,
    reuseaddr: true,
    send_timeout: 30_000,
    send_timeout_close: true
  ]

  @behaviour Transport

  @impl Transport
  def handle_connect(ip, port) do
    :gen_tcp.connect(ip, port, @options, 4000)
  end

  @impl Transport
  def handle_close(socket) do
    :gen_tcp.close(socket)
  end

  @impl Transport
  def handle_message({:tcp, socket, data}) do
    :inet.setopts(socket, active: :once)
    {:ok, data}
  end

  def handle_message({:tcp_closed, _socket}) do
    {:error, :closed}
  end

  def handle_message({:tcp_error, _socket, reason}) do
    {:error, reason}
  end

  @impl Transport
  def handle_send(socket, msg) do
    :gen_tcp.send(socket, msg)
  end
end
