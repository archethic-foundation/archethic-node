defmodule UnirisCore.P2P.NodeTCPClient do
  @moduledoc false

  @behaviour UnirisCore.P2P.NodeClientImpl

  require Logger

  use GenServer

  @tcp_options [:binary, packet: 4, active: true]

  @impl true
  @spec start_link(opts :: [ip: :inet.ip_address(), port: :inet.port_number(), parent_pid: pid()]) ::
          {:ok, pid()}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  @impl true
  def init(opts) do
    ip = Keyword.get(opts, :ip)
    port = Keyword.get(opts, :port)
    parent_pid = Keyword.get(opts, :parent_pid)

    Logger.info("Initialize P2P connection with #{inspect(ip)}:#{port}")

    {:ok, %{ip: ip, port: port, queue: :queue.new(), parent_pid: parent_pid, socket: nil},
     {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state = %{ip: ip, port: port, parent_pid: parent_pid}) do
    case :gen_tcp.connect(ip, port, @tcp_options) do
      {:ok, socket} ->
        send(parent_pid, :connected)
        {:noreply, %{state | socket: socket}}

      _ ->
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:error, :econnrefused}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:tcp, _socket, data}, state = %{queue: queue}) do
    # Decode the result
    result = :erlang.binary_to_term(data)

    # Dequeue the next client
    {{:value, client}, new_queue} = :queue.out(queue)

    GenServer.reply(client, result)
    {:noreply, %{state | queue: new_queue}}
  end

  @impl true
  def handle_call({:send_message, message}, from, state = %{socket: socket, queue: queue}) do
    message = :erlang.term_to_binary(message)
    :gen_tcp.send(socket, message)
    {:noreply, %{state | queue: :queue.in(from, queue)}}
  end

  @impl true
  @spec send_message(client :: pid(), message :: term()) ::
          response :: term()
  def send_message(pid, msg) do
    GenServer.call(pid, {:send_message, msg})
  end
end
