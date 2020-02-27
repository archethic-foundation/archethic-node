defmodule UnirisP2P.TCPClient do
  @moduledoc false

  use GenServer

  alias UnirisP2P.ClientRegistry
  alias UnirisP2P.Message

  @behaviour UnirisNetwork.P2PClient

  @tcp_options [:binary, packet: 4, active: true]

  @spec start_link(:inet.ip_address(), :inet.port_number(), binary(), pid()) :: {:ok, pid()}
  def start_link(ip, port, public_key, from) do
    GenServer.start_link(__MODULE__, [ip, port, from], name: via_tuple(public_key))
  end

  def init([ip, port, from]) do
    case :gen_tcp.connect(ip, port, @tcp_options) do
      {:ok, socket} ->
        send(from, :connected)
        {:ok, %{socket: socket, from: from}}

      {:error, reason} ->
        {:stop, {:error, reason}}
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

  def handle_info({:tcp, _, payload}, state = %{from: from}) do
    send(from, {:p2p_response, Message.decode(payload)})
    {:noreply, state}
  end

  def handle_info({:tcp_closed, reason}, state = %{from: from}) do
    {:stop, reason}
  end

  def handle_info({:tcp_error, reason}, state = %{ƒrom: from}) do
    {:stop, reason}
  end

  @spec send_message(binary(), term()) :: :ok
  def send_message(public_key, message) do
    GenServer.cast(via_tuple(public_key), {:send_message, message})
  end

  defp via_tuple(public_key) do
    {:via, Registry, {ClientRegistry, public_key}}
  end
end
