defmodule Archethic.P2P.Client.Connection do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.P2P.Client.ConnectionRegistry

  alias Archethic.P2P.MemTable
  alias Archethic.P2P.Message
  alias Archethic.P2P.MessageEnvelop

  require Logger

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter], restart: :temporary

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

  It awaiting an `{:ok, reference()}` message indicating the request have been sent to the remote socket.
  Then it awaiting an `{:ok,  Message.t()}` message indicating the success of the processing.

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

  # fetch cnnoection details from registery for a node from its public key
  defp via_tuple(public_key), do: {:via, Registry, {ConnectionRegistry, public_key}}

  def init(arg) do
    ip = Keyword.get(arg, :ip)
    port = Keyword.get(arg, :port)
    node_public_key = Keyword.get(arg, :node_public_key)
    transport = Keyword.get(arg, :transport)

    data = %{
      ip: ip,
      port: port,
      node_public_key: node_public_key,
      transport: transport,
      request_id: 0,
      messages: %{}
    }

    actions = [{:next_event, :internal, :connect}]
    {:ok, :disconnected, data, actions}
  end

  def handle_event(:enter, :disconnected, :disconnected, _data), do: :keep_state_and_data

  def handle_event(
        :enter,
        {:connected, _socket},
        :disconnected,
        data = %{node_public_key: node_public_key, messages: messages}
      ) do
    Logger.warning("Connection closed", node: Base.encode16(node_public_key))

    MemTable.decrease_node_availability(node_public_key)

    # Notify clients the connection is lost
    # and cancel the existing timeouts
    actions =
      Enum.map(messages, fn {msg_id, %{from: from, ref: ref}} ->
        send(from, {ref, {:error, :closed}})
        {{:timeout, {:request, msg_id}}, :cancel}
      end)

    # Reconnect with backoff
    actions = [{{:timeout, :reconnect}, 500, nil} | actions]
    {:keep_state, %{data | messages: %{}}, actions}
  end

  def handle_event(:enter, _old_state, {:connected, _socket}, _data), do: :keep_state_and_data

  def handle_event(
        :internal,
        :connect,
        :disconnected,
        data = %{
          ip: ip,
          port: port,
          transport: transport
        }
      ) do
    case transport.handle_connect(ip, port) do
      {:ok, socket} ->
        {:next_state, {:connected, socket}, data}

      {:error, _} ->
        actions = [{{:timeout, :reconnect}, 500, nil}]
        {:keep_state_and_data, actions}
    end
  end

  def handle_event({:timeout, :reconnect}, _event_data, :disconnected, _data) do
    actions = [{:next_event, :internal, :connect}]
    {:keep_state_and_data, actions}
  end

  def handle_event({:timeout, :reconnect}, _event_data, {:connected, _socket}, _data) do
    :keep_state_and_data
  end

  def handle_event(
        :cast,
        {:connect, from},
        state,
        data = %{
          ip: ip,
          port: port,
          transport: transport
        }
      ) do
    next_state =
      case state do
        :disconnected ->
          case transport.handle_connect(ip, port) do
            {:ok, socket} ->
              {:next_state, {:connected, socket}, data}

            {:error, _reason} ->
              :keep_state_and_data
          end

        _ ->
          :keep_state_and_data
      end

    send(from, :ok)
    next_state
  end

  def handle_event(:cast, {:send_message, ref, from, _msg, _timeout}, :disconnected, _data) do
    send(from, {ref, {:error, :closed}})
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
    message_envelop =
      MessageEnvelop.encode(
        %MessageEnvelop{
          message: message,
          message_id: request_id,
          sender_public_key: Crypto.first_node_public_key()
        },
        node_public_key
      )

    case transport.handle_send(socket, message_envelop) do
      :ok ->
        MemTable.increase_node_availability(node_public_key)

        new_data =
          data
          |> Map.update!(
            :messages,
            &Map.put(&1, request_id, %{
              from: from,
              ref: ref,
              message_name: Message.name(message),
              start_time: System.monotonic_time()
            })
          )
          |> Map.update!(:request_id, &(&1 + 1))

        actions = [{{:timeout, {:request, request_id}}, timeout, nil}]

        {:keep_state, new_data, actions}

      {:error, reason} ->
        Logger.warning("Connection failed - #{inspect(reason)}",
          node: Base.encode16(node_public_key)
        )

        send(from, {ref, {:error, :closed}})

        {:next_state, :disconnected, data}
    end
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

        {:keep_state, new_data}

      {nil, _} ->
        :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        event,
        {:connected, _socket},
        data = %{
          transport: transport,
          node_public_key: node_public_key
        }
      ) do
    case transport.handle_message(event) do
      {:error, reason} ->
        Logger.warning("Connection failed #{inspect(reason)}",
          node: Base.encode16(node_public_key)
        )

        {:next_state, :disconnected, data}

      {:ok, msg} ->
        end_time = System.monotonic_time()

        MemTable.increase_node_availability(node_public_key)

        %MessageEnvelop{
          message_id: message_id,
          message: message
        } = MessageEnvelop.decode(msg)

        case pop_in(data, [:messages, message_id]) do
          {%{
             from: from,
             ref: ref,
             start_time: start_time,
             message_name: message_name
           }, new_data} ->
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

          {nil, _state} ->
            :keep_state_and_data
        end
    end
  end
end
