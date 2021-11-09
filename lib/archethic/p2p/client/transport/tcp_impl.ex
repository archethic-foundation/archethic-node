defmodule ArchEthic.P2P.Client.Transport.TCPImpl do
  @moduledoc false

  alias ArchEthic.P2P.Client.Transport

  @options [:binary, packet: 4, active: :once]

  @behaviour Transport

  @impl Transport
  def handle_connect(ip, port) do
    :gen_tcp.connect(ip, port, @options)
  end

  @impl Transport
  def handle_message({:tcp, socket, data}) do
    :inet.setopts(socket, active: :once)
    {:ok, data}
  end

  def handle_message({:tcp_closed, _reason}) do
    {:error, :closed}
  end

  def handle_message({:tcp_error, reason}) do
    {:error, reason}
  end

  @impl Transport
  def handle_send(socket, msg) do
    :gen_tcp.send(socket, msg)
  end
end
