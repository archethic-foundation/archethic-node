defmodule Uniris.P2P.Multiplexer.Muxer do
  @moduledoc """
  Process responsible to mux messages in batch in a timeframe
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(args) do
    timeframe = Keyword.get(args, :timeframe) || 50
    multiplexer_pid = Keyword.get(args, :multiplexer_pid)

    schedule_message_sending(timeframe)

    {:ok, %{timeframe: timeframe, messages: [], stream_id: 1, multiplexer_pid: multiplexer_pid}}
  end

  @doc """
  Send data to the muxer and cache them awaiting the window timeframe to trigger the sending
  """
  @spec send_data(pid(), binary()) :: :ok
  def send_data(pid, data) do
    GenServer.cast(pid, {:send_data, data})
  end

  def handle_cast({:send_data, data}, state) do
    {:noreply, Map.update!(state, :messages, &[data | &1])}
  end

  def handle_info(
        :wrap_and_send,
        state = %{
          messages: messages,
          stream_id: stream_id,
          timeframe: timeframe,
          multiplexer_pid: multiplexer_pid
        }
      ) do
    case messages do
      [] ->
        schedule_message_sending(timeframe)
        {:noreply, state}

      _ ->
        bin_messages =
          messages
          |> Enum.map(fn <<id::32, message::binary>> ->
            <<id::32, byte_size(message)::32, message::binary>>
          end)
          |> :erlang.list_to_binary()

        send(
          multiplexer_pid,
          {:batch_sending, <<stream_id::8, length(messages)::32, bin_messages::binary>>}
        )

        schedule_message_sending(timeframe)
        {:noreply, Map.put(state, :messages, [])}
    end
  end

  defp schedule_message_sending(timeframe) do
    Process.send_after(self(), :wrap_and_send, timeframe)
  end
end
