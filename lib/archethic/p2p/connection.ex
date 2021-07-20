defmodule ArchEthic.P2P.Connection do
  @moduledoc """
  Process acting as bearer of the P2P connection and used to send and receive message
  """

  alias ArchEthic.Crypto

  alias ArchEthic.P2P.MemTable
  alias ArchEthic.P2P.Message
  alias ArchEthic.P2P.Transport

  alias ArchEthic.TaskSupervisor

  alias ArchEthic.Utils

  use GenServer

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, Keyword.take(args, [:name]))
  end

  @doc """
  Send a message through this connection and get a response otherwise get an error
  """
  @spec send_message(pid(), Message.request()) ::
          {:ok, Message.response()} | {:error, :network_issue}
  def send_message(pid, msg) when is_pid(pid) and is_struct(msg) do
    GenServer.call(pid, {:send_message, msg, Crypto.first_node_public_key()})
  end

  def init(args) do
    socket = Keyword.get(args, :socket)
    transport = Keyword.get(args, :transport)
    initiator? = Keyword.fetch!(args, :initiator?)
    node_public_key = Keyword.get(args, :node_public_key)

    {:ok,
     %{
       socket: socket,
       transport: transport,
       initiator?: initiator?,
       clients: %{},
       message_id: 0,
       tasks: %{},
       node_public_key: node_public_key
     }, {:continue, :start_receiving_loop}}
  end

  def handle_continue(:start_receiving_loop, state = %{socket: nil}), do: {:noreply, state}

  def handle_continue(:start_receiving_loop, state = %{socket: socket, transport: transport}) do
    me = self()

    Task.Supervisor.async_nolink(TaskSupervisor, __MODULE__, :receiving_loop, [
      transport,
      socket,
      me
    ])

    {:noreply, state}
  end

  def receiving_loop(transport, socket, connection_pid) do
    case Transport.read_from_socket(transport, socket) do
      {:ok, data} ->
        send(connection_pid, {:data, data})
        __MODULE__.receiving_loop(transport, socket, connection_pid)

      {:error, reason} = e ->
        Logger.info("Connection closed - #{inspect(reason)}")
        GenServer.stop(connection_pid)
        e
    end
  end

  def handle_call({:send_message, msg, _}, from, state = %{socket: nil, message_id: message_id}) do
    %Task{ref: ref} = Task.Supervisor.async_nolink(TaskSupervisor, Message, :process, [msg])

    new_state =
      state
      |> Map.update!(:clients, &Map.put(&1, message_id, from))
      |> Map.update!(:tasks, &Map.put(&1, ref, message_id))
      |> Map.update!(:message_id, &(&1 + 1))

    {:noreply, new_state}
  end

  def handle_call(
        {:send_message, msg, sender_public_key},
        from,
        state = %{
          socket: socket,
          transport: transport,
          initiator?: true,
          message_id: message_id,
          node_public_key: recipient_public_key
        }
      ) do
    message_envelop =
      build_message_envelop(message_id, msg, sender_public_key, recipient_public_key)

    %Task{ref: ref} =
      Task.Supervisor.async_nolink(TaskSupervisor, Transport, :send_message, [
        transport,
        socket,
        message_envelop
      ])

    new_state =
      state
      |> Map.update!(:clients, &Map.put(&1, message_id, from))
      |> Map.update!(:tasks, &Map.put(&1, ref, message_id))
      |> Map.update!(:message_id, &(&1 + 1))

    {:noreply, new_state}
  end

  def handle_info(
        {:data, message_envelop},
        state = %{
          initiator?: false,
          socket: socket,
          transport: transport,
          node_public_key: recipient_public_key
        }
      ) do
    {message_id, data, sender_public_key} = decode_message_envelop(message_envelop)

    MemTable.increase_node_availability(sender_public_key)

    %Task{ref: ref} =
      Task.Supervisor.async_nolink(TaskSupervisor, fn ->
        message_envelop =
          build_message_envelop(
            message_id,
            Message.process(data),
            Crypto.first_node_public_key(),
            recipient_public_key
          )

        Transport.send_message(transport, socket, message_envelop)
      end)

    new_state =
      state
      |> Map.put(:node_public_key, sender_public_key)
      |> Map.update!(:tasks, &Map.put(&1, ref, message_id))

    {:noreply, new_state}
  end

  def handle_info(
        {:data, message_envelop},
        state = %{initiator?: true, clients: clients}
      ) do
    {message_id, data, sender_public_key} = decode_message_envelop(message_envelop)
    MemTable.increase_node_availability(sender_public_key)

    case Map.get(clients, message_id) do
      nil ->
        {:noreply, state}

      from ->
        GenServer.reply(from, {:ok, data})
        {:noreply, Map.update!(state, :clients, &Map.delete(&1, message_id))}
    end
  end

  def handle_info({_task_ref, {:error, _}}, _state), do: :stop

  def handle_info({task_ref, :ok}, state) do
    {:noreply, Map.update!(state, :tasks, &Map.delete(&1, task_ref))}
  end

  def handle_info({task_ref, data}, state = %{tasks: tasks, clients: clients, socket: nil})
      when is_reference(task_ref) do
    case Map.get(tasks, task_ref) do
      nil ->
        {:noreply, state}

      message_id ->
        case Map.get(clients, message_id) do
          nil ->
            {:noreply, Map.update!(state, :tasks, &Map.delete(&1, task_ref))}

          from ->
            GenServer.reply(from, {:ok, data})

            new_state =
              state
              |> Map.update!(:tasks, &Map.delete(&1, task_ref))
              |> Map.update!(:clients, &Map.delete(&1, message_id))

            {:noreply, new_state}
        end
    end
  end

  def handle_info(
        {task_ref, data},
        state = %{
          transport: transport,
          socket: socket,
          tasks: tasks,
          node_public_key: recipient_public_key
        }
      )
      when is_reference(task_ref) do
    case Map.get(tasks, task_ref) do
      nil ->
        {:noreply, state}

      message_id ->
        message_envelop =
          build_message_envelop(
            message_id,
            data,
            Crypto.first_node_public_key(),
            recipient_public_key
          )

        Task.Supervisor.async_nolink(TaskSupervisor, Transport, :send_message, [
          transport,
          socket,
          message_envelop
        ])

        {:noreply, Map.update!(state, :tasks, &Map.delete(&1, task_ref))}
    end
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp decode_message_envelop(<<message_id::32, 0::8, curve_id::8, origin_id::8, rest::binary>>) do
    key_size = Crypto.key_size(curve_id)
    <<public_key::binary-size(key_size), rest::binary>> = rest

    {data, _} = Message.decode(rest)
    sender_public_key = <<curve_id::8, origin_id::8, public_key::binary>>
    {message_id, data, sender_public_key}
  end

  defp decode_message_envelop(<<message_id::32, 1::8, curve_id::8, origin_id::8, rest::binary>>) do
    key_size = Crypto.key_size(curve_id)
    <<public_key::binary-size(key_size), encrypted_message::binary>> = rest
    message = Crypto.ec_decrypt_with_first_node_key!(encrypted_message)

    {data, _} = Message.decode(message)

    sender_public_key = <<curve_id::8, origin_id::8, public_key::binary>>
    {message_id, data, sender_public_key}
  end

  defp build_message_envelop(message_id, message, sender_public_key, nil) do
    encoded_message =
      message
      |> Message.encode()
      |> Utils.wrap_binary()

    <<message_id::32, 0::8, sender_public_key::binary, encoded_message::binary>>
  end

  defp build_message_envelop(message_id, message, sender_public_key, recipient_public_key) do
    encrypted_message =
      message
      |> Message.encode()
      |> Utils.wrap_binary()
      |> Crypto.ec_encrypt(recipient_public_key)

    <<message_id::32, 1::8, sender_public_key::binary, encrypted_message::binary>>
  end
end
