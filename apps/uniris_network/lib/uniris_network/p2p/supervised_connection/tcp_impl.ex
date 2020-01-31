defmodule UnirisNetwork.P2P.SupervisedConnection.TCPImpl do
  @moduledoc false

  alias UnirisNetwork.P2P.SupervisedConnection.Impl

  @behaviour Impl
  @behaviour :gen_statem

  alias UnirisNetwork.Node
  alias UnirisNetwork.P2P.Message

  @tcp_options [:binary, packet: 4, active: true]

  @impl Impl
  @spec start_link(binary(), :inet.ip_address(), :inet.port_number()) :: {:ok, pid()}
  def start_link(public_key, ip, port) do
    :gen_statem.start_link(__MODULE__, [public_key, ip, port], [])
  end

  def init([public_key, ip, port]) do
    {:ok, :idle, %{ip: ip, port: port, public_key: public_key, queue: :queue.new()},
     {:next_event, :internal, :connect}}
  end

  def callback_mode, do: :handle_event_function

  def handle_event(
        :internal,
        :connect,
        _state,
        data = %{ip: ip, port: port, public_key: public_key}
  ) do
    {:ok, socket} = :gen_tcp.connect(String.to_charlist(ip), port, @tcp_options)
    Node.available(public_key)
    {:next_state, :connected, Map.put(data, :socket, socket)}
  end

  

  def handle_event(:info, {:tcp, _socket, payload}, _, data = %{queue: queue}) do
   {{:value, client}, new_queue} = :queue.out(queue)

   case Message.decode(payload) do
     {:ok, message, _public_key} ->
        {:keep_state, Map.put(data, :queue, new_queue), [{:reply, client, {:ok, message}}]}

     reason ->
        {:keep_state, Map.put(data, :queue, new_queue)}
    end
  end

  def handle_event(:info, {:tcp, _socket, payload}, _, data = %{queue: queue}) do
    :keep_state_and_data
  end

  def handle_event(:info, {:tcp_closed, _}, _state, data = %{public_key: public_key}) do
    Node.unavailable(public_key)
    {:next_state, :idle, data, {:next_event, :internal, :connect}}
  end

  def handle_event(:info, {:tcp_error, _}, _state, data = %{public_key: public_key}) do
    Node.unavailable(public_key)
    {:next_state, :idle, data, {:next_event, :internal, :connect}}
  end


  def handle_event(
        {:call, from},
        {:send_message, msg},
        _,
        data = %{socket: socket, queue: queue}
  ) do
    case :gen_tcp.send(socket, msg) do
      :ok ->
        {:keep_state, Map.put(data, :queue, :queue.in(from, queue))}

      _reason ->
        {:next_state, :error, data, [{:next_event, :internal, :connect}]}
    end
  end


  @impl Impl
  @spec send_message(pid(), binary()) :: :ok
  def send_message(pid, msg) when is_pid(pid) and is_binary(msg) do
    :gen_statem.call(pid, {:send_message, msg})
  end
end
