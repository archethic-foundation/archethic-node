defmodule UnirisP2P.TCPClient do
  @moduledoc false

  use GenServer

  alias UnirisP2P.ClientRegistry
  alias UnirisP2P.Message
  alias UnirisNetwork.Node

  @behaviour UnirisNetwork.P2P.ClientImpl

  @tcp_options [:binary, packet: 4, active: :once]

  @spec start_link(:inet.ip_address(), :inet.port_number(), UnirisCrypto.key(), pid()) :: {:ok, pid()}
  def start_link(ip, port, public_key, from) do
    GenServer.start_link(__MODULE__, [ip, port, from, public_key], name: via_tuple(public_key))
  end

  def init([ip, port, from, public_key]) do
    case :gen_tcp.connect(ip, port, @tcp_options) do
      {:ok, socket} ->
        send(from, :connected)
        {:ok, %{socket: socket, from: from, node_public_key: public_key}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_cast({:send_message, msg}, state = %{socket: socket}) do
    case :gen_tcp.send(socket, Message.encode(msg)) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_info({:tcp, _, payload}, state = %{socket: socket, from: from}) do
    send(from, {:p2p_response, Message.decode(payload)})
    :inet.setopts(socket, @tcp_options)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state = %{node_public_key: public_key}) do
    Node.unavailable(public_key)
    {:stop, :tcp_closed, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state = %{node_public_key: public_key}) do
    Node.unavailable(public_key)
    {:stop, reason, state}
  end

  @spec send_message(UnirisCrypto.key(), term()) :: :ok
  def send_message(public_key, message) do
    GenServer.cast(via_tuple(public_key), {:send_message, message})
  end

  defp via_tuple(public_key) do
    {:via, Registry, {ClientRegistry, public_key}}
  end
end
