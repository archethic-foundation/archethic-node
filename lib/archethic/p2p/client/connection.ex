defmodule ArchEthic.P2P.Client.Connection do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.P2P.Client.ConnectionRegistry

  alias ArchEthic.P2P.MemTable
  alias ArchEthic.P2P.Message
  alias ArchEthic.P2P.MessageEnvelop

  use GenServer

  use Retry

  require Logger

  @doc """
  Starts a new connection
  """
  @spec start_link(list()) :: GenServer.on_start()
  def start_link(arg \\ []) do
    node_public_key = Keyword.fetch!(arg, :node_public_key)
    GenServer.start_link(__MODULE__, arg, name: via_tuple(node_public_key))
  end

  @doc """
  Send an asynchronous message to a remote connection.

  It awaiting an `{:ok, reference()}` message indicating the request have been sent to the remote socket.
  Then it awaiting an `{:data, reference(), Message.t()}` message indicating the success of the processing.

  It may returns `{:error, :timeout}` if either the send or the receiving take more than the timeout value provided.
  It may also returns `{:error, :closed}` is the socket closed or any error in the transport layer
  ```
  """
  @spec send_message(Crypto.key(), Message.request(), timeout()) ::
          {:ok, Message.response()}
          | {:error, :timeout}
          | {:error, :closed}
  def send_message(public_key, message, timeout \\ 5_000) do
    {:ok, ref} = GenServer.call(via_tuple(public_key), {:send_message, message, timeout})

    receive do
      {:data, ^ref, data} ->
        {:ok, data}

      {:error, _} = e ->
        e
    end
  end

  defp via_tuple(public_key), do: {:via, Registry, {ConnectionRegistry, public_key}}

  def init(arg) do
    ip = Keyword.get(arg, :ip)
    port = Keyword.get(arg, :port)
    node_public_key = Keyword.get(arg, :node_public_key)
    transport = Keyword.get(arg, :transport)

    {:ok, socket} = connect(transport, ip, port, node_public_key)

    {
      :ok,
      %{
        ip: ip,
        port: port,
        node_public_key: node_public_key,
        transport: transport,
        socket: socket,
        request_id: 0,
        messages: %{}
      }
    }
  end

  def handle_call(
        {:send_message, message, timeout},
        from,
        state = %{
          socket: socket,
          request_id: request_id,
          node_public_key: node_public_key,
          transport: transport
        }
      ) do
    ref = make_ref()

    message_envelop =
      MessageEnvelop.encode(
        %MessageEnvelop{
          message: message,
          message_id: request_id,
          sender_public_key: Crypto.first_node_public_key()
        },
        node_public_key
      )

    Logger.debug("Sending #{Message.name(message)}",
      node: Base.encode16(node_public_key),
      message_id: request_id
    )

    :ok = transport.handle_send(socket, message_envelop)

    new_state =
      state
      |> Map.update!(
        :messages,
        &Map.put(&1, request_id, %{
          from: elem(from, 0),
          ref: ref,
          message_name: Message.name(message),
          timer: Process.send_after(self(), {:timeout, request_id}, timeout),
          start_time: System.monotonic_time(:millisecond)
        })
      )
      |> Map.update!(:request_id, &(&1 + 1))

    {:reply, {:ok, ref}, new_state}
  end

  def handle_info(
        {:timeout, msg_id},
        state = %{node_public_key: node_public_key}
      ) do
    case pop_in(state, [:messages, msg_id]) do
      {%{from: from, timer: timer, message_name: message_name}, new_state} ->
        Logger.debug("Message #{message_name} reaches its timeout",
          node: Base.encode16(node_public_key),
          message_id: msg_id
        )

        Process.cancel_timer(timer)
        send(from, {:error, :timeout})
        {:noreply, new_state}

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info(
        event,
        state = %{
          ip: ip,
          port: port,
          transport: transport,
          node_public_key: node_public_key,
          messages: messages
        }
      ) do
    case transport.handle_message(event) do
      {:error, reason} ->
        MemTable.decrease_node_availability(node_public_key)

        Logger.warning("Connection disconnected #{inspect(reason)}",
          node: Base.encode16(node_public_key)
        )

        Enum.each(messages, fn {_, %{from: from, timer: timer}} ->
          send(from, {:error, :closed})
          Process.cancel_timer(timer)
        end)

        {:ok, socket} = connect(transport, ip, port, node_public_key)
        {:noreply, %{state | socket: socket, messages: %{}}}

      {:ok, msg} ->
        end_time = System.monotonic_time(:millisecond)

        MemTable.increase_node_availability(node_public_key)

        %MessageEnvelop{
          message_id: message_id,
          message: message
        } = MessageEnvelop.decode(msg)

        case pop_in(state, [:messages, message_id]) do
          {%{
             from: from,
             ref: ref,
             timer: timer,
             start_time: start_time,
             message_name: message_name
           }, new_state} ->
            Logger.debug("Message #{message_name} took #{end_time - start_time} ms",
              message_id: message_id,
              node_public_key: node_public_key
            )

            send(from, {:data, ref, message})
            Process.cancel_timer(timer)
            {:noreply, new_state}

          {nil, _state} ->
            {:noreply, state}
        end
    end
  end

  defp connect(transport, ip, port, node_public_key) do
    retry_while with: exponential_backoff(100, 2) do
      case transport.handle_connect(ip, port) do
        {:ok, socket} ->
          {:halt, {:ok, socket}}

        {:error, reason} ->
          Logger.warning(
            "Error during node connection #{inspect(reason)} to #{:inet.ntoa(ip)}:#{port}",
            node: Base.encode16(node_public_key)
          )

          {:cont, {:error, reason}}
      end
    end
  end
end
