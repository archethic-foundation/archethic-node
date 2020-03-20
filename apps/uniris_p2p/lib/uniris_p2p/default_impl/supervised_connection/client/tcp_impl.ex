defmodule UnirisP2P.DefaultImpl.SupervisedConnection.Client.TCPImpl do
  @moduledoc false

  require Logger

  @behaviour UnirisP2P.DefaultImpl.SupervisedConnection.Client.Impl

  @tcp_options [:binary, packet: 4, active: true]

  @impl true
  @spec start_link(ip :: :inet.adress(), port :: :inet.port_number(), parent :: pid()) ::
          {:ok, pid()}
  def start_link(ip, port, parent) do
    GenServer.start_link(__MODULE__, [ip, port, parent])
  end

  def init([ip, port, parent]) do
    socket = connect(ip, port, parent)
    {:ok, %{ip: ip, port: port, socket: socket, parent: parent, queue: :queue.new()}}
  end

  defp connect(ip, port, parent) do
    case :gen_tcp.connect(ip, port, @tcp_options) do
      {:ok, socket} ->
        # Notify the supervised connection process (parent) about the connection
        send(parent, :connected)
        socket

      _ ->
        # Notify the supervised connection process (parent) about the disconnection
        send(parent, :disconnected)
        # Try to the reconnect
        connect(ip, port, parent)
    end
  end

  def handle_info({:tcp, _socket, data}, state = %{queue: queue}) do
    # Decode the result
    result = :erlang.binary_to_term(data)

    # Dequeue the next client
    {{:value, client}, new_queue} = :queue.out(queue)

    GenServer.reply(client, {:ok, result})
    {:noreply, %{state | queue: new_queue}}
  end

  def handle_info({:tcp_closed, _socket}, state = %{ip: ip, port: port, parent: parent}) do
    # Notify the supervised connection process (parent) about the disconnection
    send(parent, :disconnected)

    # Try to reconnect
    socket = connect(ip, port, parent)
    {:noreply, %{state | socket: socket}}
  end

  def handle_info({:error, :econnrefused}, state = %{ip: ip, port: port, parent: parent}) do
    # Notify the supervised connection process (parent) about the disconnection
    send(parent, :disconnected)

    # Try to reconnect
    socket = connect(ip, port, parent)
    {:noreply, Map.put(state, :socket, socket)}
  end

  def handle_call({:send_message, message}, from, state = %{socket: socket, queue: queue}) do
    # Encode and send the message
    :gen_tcp.send(socket, :erlang.term_to_binary(message))

    # Enqueue the client
    state = %{state | queue: :queue.in(from, queue)}

    # Delay the reply
    {:noreply, state}
  end

  @impl true
  @spec send_message(pid, term()) :: term()
  def send_message(pid, message) do
    GenServer.call(pid, {:send_message, message})
  end
end
