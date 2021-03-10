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

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(args) do
    socket = Keyword.get(args, :socket)
    transport = Keyword.get(args, :transport)
    recv_handler = Keyword.get(args, :recv_handler)
    # timeframe = Keyword.get(args, :timeframe)

    {:ok, muxer_pid} =
      Muxer.start_link(multiplexer_pid: self(), socket: socket, transport: transport)

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
       queue: %{}
     }}
  end

  @doc """
  Send a data to through the stream multiplexer and add it to the `Muxer` waiting the window of sending.
  The calling process is queue as client awaiting the response.
  """
  @spec send_data(pid(), binary(), timeout()) ::
          {:ok, binary()} | {:error, :closed | :inet.posix()}
  def send_data(pid, data, timeout \\ 3_000) do
    GenServer.call(pid, {:send_data, data}, timeout)
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}
  end

  @doc """
  Notify the responses to the awaiting clients
  """
  @spec notify_clients(pid(), non_neg_integer(), binary()) :: :ok
  def notify_clients(pid, id, data) do
    GenServer.cast(pid, {:notify_clients, id, data})
  end

  def handle_call({:send_data, data}, from, state = %{muxer_pid: muxer_pid}) do
    case Muxer.send_data(muxer_pid, data) do
      {:ok, stream_id} ->
        {:noreply, Map.update!(state, :queue, &Map.put(&1, stream_id, from))}

      {:error, _} = e ->
        {:reply, e, state}
    end
  end

  def handle_cast({:notify_clients, id, data}, state = %{queue: queue}) do
    case Map.pop(queue, id) do
      {nil, _} ->
        Logger.warning("No queued message")
        {:noreply, state}

      {pid, queue} ->
        GenServer.reply(pid, {:ok, data})
        {:noreply, Map.put(state, :queue, queue)}
    end
  end

  # def handle_info(
  #       {:batch_sending, data},
  #       state = %{socket: socket, transport: transport, queue: queue}
  #     ) do
  #   case Transport.send_message(transport, socket, data) do
  #     :ok ->
  #       :ok

  #     {:error, reason} = e ->
  #       notify_error_to_clients(e, data, queue)
  #       Logger.info("Connection closed - #{reason}")
  #   end

  #   {:noreply, state}
  # end

  # defp notify_error_to_clients(e = {:error, _}, data, queue) do
  #   data
  #   |> Demuxer.decode_data()
  #   |> Enum.each(fn <<id::32, _::binary>> ->
  #     case Map.pop(queue, id) do
  #       {nil, _} ->
  #         Logger.warning("No queued message")

  #       {pid, _queue} ->
  #         GenServer.reply(pid, e)
  #     end
  #   end)
  # end
end
