defmodule Uniris.P2P.Multiplexer do
  @moduledoc """
  Allow to send multiple message through a single connection to a remote node
  using multiplexing through a muxer and demuxer.

  Messages are sent on batch according to the `Muxer` policy.
  """

  use GenServer

  require Logger

  alias __MODULE__.Demuxer
  alias __MODULE__.Muxer

  alias Uniris.P2P.Transport

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(args) do
    socket = Keyword.get(args, :socket)
    transport = Keyword.get(args, :transport)
    recv_handler = Keyword.get(args, :recv_handler)
    timeframe = Keyword.get(args, :timeframe)

    {:ok, muxer_pid} = Muxer.start_link(multiplexer_pid: self(), timeframe: timeframe)

    {:ok, demuxer_pid} =
      Demuxer.start_link(
        socket: socket,
        muxer_pid: muxer_pid,
        multiplexer_pid: self(),
        transport: transport,
        recv_handler: recv_handler
      )

    {:ok,
     %{
       transport: transport,
       socket: socket,
       muxer_pid: muxer_pid,
       demuxer_pid: demuxer_pid,
       next_id: 1,
       queue: %{}
     }}
  end

  @doc """
  Send a data to through the stream multiplexer and add it to the `Muxer` waiting the window of sending.
  The calling process is queue as client awaiting the response.
  """
  @spec send_data(pid(), binary()) :: {:ok, binary()} | {:error, :closed | :inet.posix()}
  def send_data(pid, data) do
    GenServer.call(pid, {:send_data, data})
  end

  @doc """
  Notify the responses to the awaiting clients
  """
  @spec notify_clients(pid(), binary()) :: :ok
  def notify_clients(pid, responses) do
    GenServer.cast(pid, {:notify_clients, responses})
  end

  def handle_call({:send_data, data}, from, state = %{muxer_pid: muxer_pid, next_id: next_id}) do
    Muxer.send_data(muxer_pid, <<next_id::32, data::binary>>)

    new_state =
      state
      |> Map.update!(:next_id, &(&1 + 1))
      |> Map.update!(:queue, &Map.put(&1, next_id, from))

    {:noreply, new_state}
  end

  def handle_cast({:notify_clients, responses}, state = %{queue: queue}) do
    new_state =
      Enum.reduce(responses, state, fn <<id::32, data::binary>>, acc ->
        case Map.pop(queue, id) do
          {nil, _} ->
            Logger.warning("No queued message")
            acc

          {pid, queue} ->
            GenServer.reply(pid, {:ok, data})
            Map.put(acc, :queue, queue)
        end
      end)

    {:noreply, new_state}
  end

  def handle_info(
        {:batch_sending, data},
        state = %{socket: socket, transport: transport, queue: queue}
      ) do
    case Transport.send_message(transport, socket, data) do
      :ok ->
        :ok

      {:error, reason} = e ->
        notify_error_to_clients(e, data, queue)
        Logger.info("Connection closed - #{reason}")
    end

    {:noreply, state}
  end

  defp notify_error_to_clients(e = {:error, _}, data, queue) do
    data
    |> Demuxer.decode_data()
    |> Enum.each(fn <<id::32, _::binary>> ->
      case Map.pop(queue, id) do
        {nil, _} ->
          Logger.warning("No queued message")

        {pid, _queue} ->
          GenServer.reply(pid, e)
      end
    end)
  end
end
