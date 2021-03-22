defmodule Uniris.P2P.Multiplexer.Muxer do
  @moduledoc """
  Process responsible to mux messages in batch in a timeframe
  """

  use GenServer

  alias Uniris.P2P.Transport

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(args) do
    socket = Keyword.get(args, :socket)
    transport = Keyword.get(args, :transport)

    {:ok, %{stream_id: 1, transport: transport, socket: socket}}
  end

  @doc """
  Send data to the muxer and cache them awaiting the window timeframe to trigger the sending
  """
  @spec send_data(pid(), binary()) ::
          {:ok, stream_id :: non_neg_integer()} | {:error, :inet.posix()}
  def send_data(pid, data) when is_pid(pid) and is_binary(data) do
    GenServer.call(pid, {:send_data, data})
  end

  @doc """
  Send data to the muxer and cache them awaiting the window timeframe to trigger the sending
  """
  @spec send_data(pid(), non_neg_integer(), binary()) ::
          {:ok, stream_id :: non_neg_integer()} | {:error, :inet.posix()}
  def send_data(pid, id, data)
      when is_pid(pid) and is_integer(id) and id > 0 and is_binary(data) do
    GenServer.call(pid, {:send_data, id, data})
  end

  def handle_call(
        {:send_data, data},
        _,
        state = %{stream_id: stream_id, socket: socket, transport: transport}
      ) do
    case Transport.send_message(transport, socket, <<stream_id::32, data::binary>>) do
      :ok ->
        {:reply, {:ok, stream_id}, Map.update!(state, :stream_id, &(&1 + 1))}

      {:error, _} = e ->
        {:reply, e, state}
    end
  end

  def handle_call({:send_data, id, data}, _, state = %{socket: socket, transport: transport}) do
    case Transport.send_message(transport, socket, <<id::32, data::binary>>) do
      :ok ->
        {:reply, {:ok, id}, state}

      {:error, _} = e ->
        {:reply, e, state}
    end
  end
end
