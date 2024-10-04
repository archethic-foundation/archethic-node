defmodule Archethic.P2P.Client.Connection do
  @moduledoc """

  3 states:
    :initializing
    {:connected, socket}
    :disconnected

  we use the :initializing state to be able to postpone calls and casts until after the 1 connect attempt
  """

  alias Archethic.Crypto

  alias Archethic.P2P.Client.ConnectionRegistry

  alias Archethic.P2P.Message
  alias Archethic.P2P.MessageEnvelop

  alias Archethic.Utils

  require Logger

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter], restart: :temporary
  @vsn 2
  @table_name :connection_status

  @heartbeat_interval Keyword.get(
                        Application.compile_env(:archethic, __MODULE__, []),
                        :heartbeat_interval,
                        10_000
                      )
  @reconnect_delay Keyword.get(
                     Application.compile_env(:archethic, __MODULE__, []),
                     :reconnect_delay,
                     500
                   )

  @doc """
  Starts a new connection
  """
  @spec start_link(list()) :: GenServer.on_start()
  def start_link(arg \\ []) do
    node_public_key = Keyword.fetch!(arg, :node_public_key)
    GenStateMachine.start_link(__MODULE__, arg, name: via_tuple(node_public_key))
  end

  @doc """
  Send an asynchronous message to a remote connection.

  The process will try to send the message to the remote node.

  It may returns `{:error, :timeout}` if either the send or the receiving take more than the timeout value provided.
  It may also returns `{:error, :closed}` is the socket closed or any error in the transport layer
  """
  @spec send_message(Crypto.key(), Message.request(), timeout()) ::
          {:ok, Message.response()}
          | {:error, :timeout}
          | {:error, :closed}
  def send_message(public_key, message, timeout \\ 3_000) do
    ref = make_ref()

    GenStateMachine.cast(via_tuple(public_key), {:send_message, ref, self(), message, timeout})

    receive do
      {^ref, msg} ->
        msg
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  When called, if disconnect, it will try to connect to socket
  Noop if it's already connected

  It's used when some node has been offline for a long time
  It has connected to us so we know we can connect to it as well
  """
  @spec wake_up(Crypto.key()) :: :ok
  def wake_up(public_key) do
    GenStateMachine.cast(via_tuple(public_key), :wake_up)
  end

  @doc """
  Get the availability timer and reset it with a new start time if it was already started
  """
  @spec get_availability_timer(Crypto.key(), boolean()) :: non_neg_integer()
  def get_availability_timer(public_key, reset?) do
    GenStateMachine.call(via_tuple(public_key), {:get_timer, reset?})
  end

  @doc """
  Return true if the connection is established
  """
  @spec connected?(node_public_key :: Crypto.key()) :: boolean()
  def connected?(node_public_key) do
    case :ets.lookup(@table_name, node_public_key) do
      [{_key, connected?}] -> connected?
      _ -> false
    end
  end

  defp set_node_connected(node_public_key),
    do: :ets.insert(@table_name, {node_public_key, true})

  defp set_node_disconnected(node_public_key),
    do: :ets.insert(@table_name, {node_public_key, false})

  # fetch connection details from registery for a node from its public key
  defp via_tuple(public_key), do: {:via, Registry, {ConnectionRegistry, public_key}}

  def init(arg) do
    ip = Keyword.get(arg, :ip)
    port = Keyword.get(arg, :port)
    node_public_key = Keyword.get(arg, :node_public_key)
    transport = Keyword.get(arg, :transport)
    from = Keyword.get(arg, :from)

    data = %{
      ip: ip,
      port: port,
      node_public_key: node_public_key,
      transport: transport,
      request_id: 0,
      messages: %{},
      send_tasks: %{},
      availability_timer: {nil, 0},
      reconnect_attempts: 0,
      heartbeats_sent: 0,
      heartbeats_received: 0
    }

    {:ok, :initializing, data, [{:next_event, :internal, {:connect, from}}]}
  end

  # every messages sent while inializing will wait until state changes
  def handle_event({:call, _}, _action, :initializing, _data) do
    {:keep_state_and_data, :postpone}
  end

  # every messages sent while inializing will wait until state changes
  def handle_event(:cast, _action, :initializing, _data) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event(
        {:call, from},
        {:get_timer, reset?},
        _state,
        data = %{availability_timer: availability_timer}
      ) do
    time =
      case availability_timer do
        {nil, time} ->
          time

        {start, time} ->
          time + (System.monotonic_time(:second) - start)
      end

    if reset? do
      new_data =
        Map.update!(data, :availability_timer, fn
          {nil, _} ->
            {nil, 0}

          _ ->
            {System.monotonic_time(:second), 0}
        end)

      {:keep_state, new_data, {:reply, from, time}}
    else
      {:keep_state_and_data, {:reply, from, time}}
    end
  end

  # Handle only used for testing
  def handle_event(:info, :start_timer, _state, data) do
    {:keep_state,
     Map.update!(data, :availability_timer, fn
       {nil, time} -> {System.monotonic_time(:second), time}
       timer -> timer
     end)}
  end

  def handle_event(
        :enter,
        {:connected, _socket},
        :disconnected,
        data = %{node_public_key: node_public_key, messages: messages}
      ) do
    Logger.warning("Connection closed", node: Base.encode16(node_public_key))

    set_node_disconnected(node_public_key)

    # Stop availability timer
    new_data =
      data
      |> Map.put(:messages, %{})
      |> Map.update!(:availability_timer, fn
        {nil, time} ->
          {nil, time}

        {start, previous_time} ->
          added_time = System.monotonic_time(:second) - start
          {nil, previous_time + added_time}
      end)

    # Notify clients the connection is lost
    # and cancel the existing timeouts
    actions =
      Enum.map(messages, fn {msg_id, %{from: from, ref: ref}} ->
        send(from, {ref, {:error, :closed}})
        {{:timeout, {:request, msg_id}}, :cancel}
      end)

    # Reconnect with backoff
    actions = [{{:timeout, :reconnect}, backoff(data.reconnect_attempts), nil} | actions]
    {:keep_state, new_data, actions}
  end

  def handle_event(
        :enter,
        _,
        {:connected, _socket},
        data = %{node_public_key: node_public_key}
      ) do
    set_node_connected(node_public_key)

    # Start availability timer
    new_data =
      data
      |> Map.put(:reconnect_attempts, 0)
      |> Map.put(:heartbeats_sent, 0)
      |> Map.put(:heartbeats_received, 0)
      |> Map.update!(:availability_timer, fn
        {nil, time} ->
          {System.monotonic_time(:second), time}

        timer ->
          timer
      end)

    Process.send_after(self(), :heartbeat, @heartbeat_interval)

    {:keep_state, new_data}
  end

  def handle_event(:enter, _old_state, :initializing, _data), do: :keep_state_and_data
  def handle_event(:enter, _old_state, :disconnected, _data), do: :keep_state_and_data

  # called from the :disconnected or :initializing state
  def handle_event(
        :internal,
        {:connect, from},
        _state,
        _data = %{
          ip: ip,
          port: port,
          transport: transport
        }
      ) do
    # try to connect asynchronously so it does not block the messages coming in
    # Task.async/1 will send a {:info, {ref, result}} message to the connection process
    me = self()

    Task.async(fn ->
      case transport.handle_connect(ip, port) do
        {:ok, socket} when is_port(socket) ->
          :gen_tcp.controlling_process(socket, me)
          {:ok, socket, from}

        # only used for tests (make_ref())
        {:ok, socket} ->
          {:ok, socket, from}

        {:error, reason} ->
          {:error, reason, from}
      end
    end)

    :keep_state_and_data
  end

  # this message is used to delay next connection attempt
  def handle_event({:timeout, :reconnect}, _event_data, {:connected, _socket}, _data) do
    :keep_state_and_data
  end

  # this message is used to delay next connection attempt
  def handle_event({:timeout, :reconnect}, _event_data, _state, data) do
    actions = [{:next_event, :internal, {:connect, nil}}]

    new_data = Map.update!(data, :reconnect_attempts, &(&1 + 1))
    {:keep_state, new_data, actions}
  end

  def handle_event(
        :cast,
        {:send_message, ref, from, _msg, _timeout},
        :disconnected,
        _data
      ) do
    send(from, {ref, {:error, :closed}})
    :keep_state_and_data
  end

  def handle_event(
        :cast,
        :wake_up,
        :disconnected,
        data
      ) do
    actions = [{:next_event, :internal, {:connect, nil}}]
    {:keep_state, %{data | reconnect_attempts: 0}, actions}
  end

  def handle_event(
        :cast,
        :wake_up,
        _,
        _data
      ) do
    :keep_state_and_data
  end

  def handle_event(
        :cast,
        {:send_message, ref, from, message, timeout},
        {:connected, socket},
        data = %{
          request_id: request_id,
          node_public_key: node_public_key,
          transport: transport
        }
      ) do
    %Task{ref: task_ref} =
      Task.async(fn ->
        start_encoding_time = System.monotonic_time()

        signature =
          message
          |> Message.encode()
          |> Utils.wrap_binary()
          |> Crypto.sign_with_first_node_key()

        message_envelop =
          MessageEnvelop.encode(
            %MessageEnvelop{
              message: message,
              message_id: request_id,
              sender_public_key: Crypto.first_node_public_key(),
              signature: signature
            },
            node_public_key
          )

        :telemetry.execute(
          [:archethic, :p2p, :encode_message],
          %{
            duration: System.monotonic_time() - start_encoding_time
          },
          %{message: Message.name(message)}
        )

        start_transport_sending_time = System.monotonic_time()
        res = transport.handle_send(socket, message_envelop)

        :telemetry.execute(
          [:archethic, :p2p, :transport_sending_message],
          %{
            duration: System.monotonic_time() - start_transport_sending_time
          },
          %{message: Message.name(message)}
        )

        res
      end)

    new_data =
      data
      |> Map.update!(
        :messages,
        &Map.put(&1, request_id, %{
          from: from,
          ref: ref,
          message_name: Message.name(message),
          start_time: System.monotonic_time(),
          sending_task_ref: task_ref,
          timeout: timeout
        })
      )
      |> Map.update!(:send_tasks, &Map.put(&1, task_ref, request_id))
      |> Map.update!(:request_id, &(&1 + 1))

    actions = [{{:timeout, {:request, request_id}}, timeout, nil}]
    {:keep_state, new_data, actions}
  end

  def handle_event({:timeout, _}, _, :disconnected, _data), do: :keep_state_and_data

  def handle_event(
        {:timeout, {:request, msg_id}},
        _event_data,
        {:connected, _socket},
        data = %{node_public_key: node_public_key}
      ) do
    case pop_in(data, [:messages, msg_id]) do
      {%{message_name: message_name}, new_data} ->
        Logger.debug("Message #{message_name} reaches its timeout",
          node: Base.encode16(node_public_key),
          message_id: msg_id
        )

        set_node_disconnected(node_public_key)

        # Stop availability timer
        new_data =
          Map.update!(new_data, :availability_timer, fn
            {nil, time} ->
              {nil, time}

            {start, previous_time} ->
              added_time = System.monotonic_time(:second) - start
              {nil, previous_time + added_time}
          end)

        {:keep_state, new_data}

      {nil, _} ->
        :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        :heartbeat,
        {:connected, socket},
        data = %{
          transport: transport,
          heartbeats_sent: heartbeats_sent,
          heartbeats_received: heartbeats_received
        }
      ) do
    # disconnect if missed more than 2 heartbeats
    if heartbeats_sent - heartbeats_received >= 2 do
      transport.handle_close(socket)
      {:next_state, :disconnected, data}
    else
      transport.handle_send(socket, "hb")
      Process.send_after(self(), :heartbeat, @heartbeat_interval)
      {:keep_state, %{data | heartbeats_sent: heartbeats_sent + 1}}
    end
  end

  def handle_event(
        :info,
        :heartbeat,
        _state,
        _data
      ) do
    :keep_state_and_data
  end

  def handle_event(:info, {ref, :ok}, {:connected, _socket}, data = %{send_tasks: send_tasks}) do
    case Map.pop(send_tasks, ref) do
      {nil, _} ->
        :keep_state_and_data

      {_, new_send_tasks} ->
        {:keep_state, Map.put(data, :send_tasks, new_send_tasks)}
    end
  end

  def handle_event(
        :info,
        {ref, {:error, reason}},
        {:connected, _socket},
        data = %{messages: messages, send_tasks: send_tasks, node_public_key: node_public_key}
      ) do
    Logger.warning("Message sending failed - #{inspect(reason)}",
      node: Base.encode16(node_public_key)
    )

    case Map.pop(send_tasks, ref) do
      {nil, _} ->
        {:next_state, :disconnected, data}

      {request_id, new_send_tasks} ->
        new_data =
          case Map.pop(messages, request_id) do
            {%{from: from, ref: ref}, new_messages} ->
              send(from, {ref, {:error, :closed}})

              data
              |> Map.put(:messages, new_messages)
              |> Map.put(:send_tasks, new_send_tasks)

            {nil, _} ->
              Map.put(data, :send_tasks, new_send_tasks)
          end

        {:next_state, :disconnected, new_data}
    end
  end

  # Task.async tells us the process ended successfully
  def handle_event(:info, {:DOWN, _ref, :process, _pid, :normal}, _, _data) do
    :keep_state_and_data
  end

  # Task.async sending us the result of the handle_connect
  def handle_event(:info, {_ref, {:ok, socket, nil}}, _, data) do
    {:next_state, {:connected, socket}, data}
  end

  def handle_event(:info, {_ref, {:ok, socket, from}}, _, data) do
    send(from, :connected)
    {:next_state, {:connected, socket}, data}
  end

  # Task.async sending us the result of the handle_connect
  def handle_event(:info, {_ref, {:error, _reason, nil}}, _, data) do
    actions = [{{:timeout, :reconnect}, backoff(data.reconnect_attempts), nil}]
    {:next_state, :disconnected, data, actions}
  end

  def handle_event(:info, {_ref, {:error, reason, from}}, _, data) do
    send(from, {:error, reason})
    actions = [{{:timeout, :reconnect}, backoff(data.reconnect_attempts), nil}]
    {:next_state, :disconnected, data, actions}
  end

  def handle_event(
        :info,
        event,
        {:connected, _socket},
        data = %{
          transport: transport,
          node_public_key: node_public_key,
          heartbeats_received: heartbeats_received
        }
      ) do
    case transport.handle_message(event) do
      {:error, reason} ->
        Logger.warning("Connection failed #{inspect(reason)}",
          node: Base.encode16(node_public_key)
        )

        {:next_state, :disconnected, data}

      {:ok, "hb"} ->
        {:keep_state, %{data | heartbeats_received: heartbeats_received + 1}}

      {:ok, msg} ->
        set_node_connected(node_public_key)

        # Start availability timer
        new_data =
          Map.update!(data, :availability_timer, fn
            {nil, time} ->
              {System.monotonic_time(:second), time}

            {start, time} ->
              {start, time}
          end)

        start_decoding_time = System.monotonic_time()

        %MessageEnvelop{
          message_id: message_id,
          message: message,
          signature: signature,
          decrypted_raw_message: decrypted_raw_message
        } = MessageEnvelop.decode(msg)

        :telemetry.execute(
          [:archethic, :p2p, :decode_message],
          %{
            duration: System.monotonic_time() - start_decoding_time
          },
          %{message: Message.name(message)}
        )

        with true <-
               Crypto.verify?(
                 signature,
                 decrypted_raw_message,
                 node_public_key
               ),
             {%{
                from: from,
                ref: ref,
                start_time: start_time,
                message_name: message_name
              }, new_data} <- pop_in(new_data, [:messages, message_id]) do
          end_time = System.monotonic_time()

          :telemetry.execute(
            [:archethic, :p2p, :send_message],
            %{
              duration: end_time - start_time
            },
            %{message: message_name}
          )

          send(from, {ref, {:ok, message}})

          actions = [{{:timeout, {:message, msg}}, :cancel}]

          {:keep_state, new_data, actions}
        else
          _ ->
            :keep_state_and_data
        end
    end
  end

  def handle_event(:info, _, _, _data) do
    # Unhandled message received
    :keep_state_and_data
  end

  def terminate(_, _, %{node_public_key: node_public_key}) do
    :ets.delete(@table_name, node_public_key)
  end

  def code_change(1, state, data, _extra) do
    {:ok, state,
     data
     |> Map.merge(%{
       reconnect_attempts: 0,
       heartbeats_sent: 0,
       heartbeats_received: 0
     })}
  end

  def code_change(_old_vsn, state, data, _extra), do: {:ok, state, data}

  defp backoff(attempts) do
    config = Application.get_env(:archethic, __MODULE__, [])

    case Keyword.get(config, :backoff_strategy, :exponential) do
      :static ->
        @reconnect_delay

      :exponential ->
        # cap at a few hours
        min(:timer.hours(6), 2 ** attempts * @reconnect_delay)
    end
  end
end
