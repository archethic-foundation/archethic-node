defmodule Uniris.P2P.Connection do
  @moduledoc """
  Process acting as bearer of the P2P connection and used to send and receive message
  """

  alias Uniris.P2P.Message
  alias Uniris.P2P.Transport

  alias Uniris.Utils

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
    GenServer.call(pid, {:send_message, msg})
  end

  def init(args) do
    socket = Keyword.get(args, :socket)
    transport = Keyword.get(args, :transport)
    initiator? = Keyword.fetch!(args, :initiator?)

    {:ok,
     %{
       socket: socket,
       transport: transport,
       initiator?: initiator?,
       clients: %{},
       message_id: 0,
       tasks: %{}
     }, {:continue, :start_receiving_loop}}
  end

  def handle_continue(:start_receiving_loop, state = %{socket: nil}), do: {:noreply, state}

  def handle_continue(:start_receiving_loop, state = %{socket: socket, transport: transport}) do
    me = self()
    Task.async(fn -> loop_data(transport, socket, me) end)

    {:noreply, state}
  end

  defp loop_data(transport, socket, connection_pid) do
    case Transport.read_from_socket(transport, socket) do
      {:ok, data} ->
        send(connection_pid, {:data, data})
        loop_data(transport, socket, connection_pid)

      {:error, reason} = e ->
        Logger.info("Connection closed - #{inspect(reason)}")
        GenServer.stop(connection_pid)
        e
    end
  end

  def handle_call({:send_message, msg}, from, state = %{socket: nil, message_id: message_id}) do
    %Task{ref: ref} = Task.async(fn -> Message.process(msg) end)

    new_state =
      state
      |> Map.update!(:clients, &Map.put(&1, message_id, from))
      |> Map.update!(:tasks, &Map.put(&1, ref, message_id))
      |> Map.update!(:message_id, &(&1 + 1))

    {:noreply, new_state}
  end

  def handle_call(
        {:send_message, msg},
        from,
        state = %{socket: socket, transport: transport, initiator?: true, message_id: message_id}
      ) do
    encoded_message = msg |> Message.encode() |> Utils.wrap_binary()

    %Task{ref: ref} =
      Task.async(fn ->
        Transport.send_message(transport, socket, <<message_id::32, encoded_message::binary>>)
      end)

    new_state =
      state
      |> Map.update!(:clients, &Map.put(&1, message_id, from))
      |> Map.update!(:tasks, &Map.put(&1, ref, message_id))
      |> Map.update!(:message_id, &(&1 + 1))

    {:noreply, new_state}
  end

  def handle_info(
        {:data, <<message_id::32, data::binary>>},
        state = %{initiator?: false, socket: socket, transport: transport}
      ) do
    %Task{ref: ref} =
      Task.async(fn ->
        {msg, _} = Message.decode(data)

        encoded_message =
          msg
          |> Message.process()
          |> Message.encode()
          |> Utils.wrap_binary()

        Transport.send_message(transport, socket, <<message_id::32, encoded_message::binary>>)
      end)

    {:noreply, Map.update!(state, :tasks, &Map.put(&1, ref, message_id))}
  end

  def handle_info(
        {:data, <<message_id::32, data::binary>>},
        state = %{initiator?: true, clients: clients}
      ) do
    case Map.get(clients, message_id) do
      nil ->
        {:noreply, state}

      from ->
        {message, _} = Message.decode(data)

        GenServer.reply(from, {:ok, message})
        {:noreply, Map.update!(state, :clients, &Map.delete(&1, message_id))}
    end
  end

  def handle_info({_task_ref, {:error, _}}, _state), do: :stop

  def handle_info({task_ref, :ok}, state) do
    {:noreply, Map.update!(state, :tasks, &Map.delete(&1, task_ref))}
  end

  def handle_info({task_ref, data}, state = %{tasks: tasks, clients: clients, socket: nil}) when is_reference(task_ref) do
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
        state = %{transport: transport, socket: socket, tasks: tasks}
      ) when is_reference(task_ref) do
    case Map.get(tasks, task_ref) do
      nil ->
        {:noreply, state}

      message_id ->
        encoded_message =
          data
          |> Message.encode()
          |> Utils.wrap_binary()

        Task.async(fn ->
          Transport.send_message(transport, socket, <<message_id::32, encoded_message::binary>>)
        end)

        {:noreply, Map.update!(state, :tasks, &Map.delete(&1, task_ref))}
    end
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
