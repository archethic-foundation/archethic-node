defmodule Archethic.Contracts.WasmMemory do
  @moduledoc false
  use GenServer

  @vsn 1

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def set_input(pid, input) do
    GenServer.cast(pid, {:set_input, input})
  end

  def input_size(pid) do
    GenServer.call(pid, :input_size)
  end

  def alloc(pid, size) do
    GenServer.call(pid, {:alloc, size})
  end

  def store_u8(pid, offset, data) do
    GenServer.cast(pid, {:store_u8, offset, data})
  end

  def set_output(pid, offset, length) do
    GenServer.cast(pid, {:set_output, offset, length})
  end

  def get_output(pid) do
    GenServer.call(pid, :get_output)
  end

  def set_error(pid, offset, length) do
    GenServer.cast(pid, {:set_error, offset, length})
  end

  def get_error(pid) do
    GenServer.call(pid, :get_error)
  end

  def read(pid, offset, length) do
    GenServer.call(pid, {:read, offset, length})
  end

  def clear(pid) do
    GenServer.call(pid, :clear)
  end

  def init(_) do
    {:ok,
     %{
       input: <<>>,
       buffer: <<>>,
       buffer_offset: 0
     }}
  end

  def handle_cast({:set_input, input}, state = %{buffer: buffer, buffer_offset: buffer_offset}) do
    input_size = byte_size(input)
    extended_output = <<buffer::binary, input::binary>>

    {:noreply,
     %{state | buffer: extended_output, buffer_offset: buffer_offset + input_size, input: input}}
  end

  def handle_cast({:store_u8, 0, data}, state = %{buffer: <<_::8, remaining::binary>>}) do
    {:noreply, %{state | buffer: <<data::8, remaining::binary>>}}
  end

  def handle_cast(
        {:store_u8, offset, data},
        state = %{buffer: buffer}
      ) do
    offset_size = offset * 8
    <<prev::size(offset_size), _::8, remaining::binary>> = buffer

    {:noreply,
     %{
       state
       | buffer: <<prev::size(offset_size), data::8, remaining::binary>>
     }}
  end

  def handle_cast({:set_output, offset, length}, state = %{buffer: buffer}) do
    {:noreply, Map.put(state, :output, :erlang.binary_part(buffer, offset, length))}
  end

  def handle_cast({:set_error, offset, length}, state = %{buffer: buffer}) do
    err_payload = :erlang.binary_part(buffer, offset, length)
    err = Jason.decode!(err_payload)
    {:noreply, Map.put(state, :error, err)}
  end

  def handle_call(
        {:alloc, size},
        _from,
        state = %{buffer: buffer, buffer_offset: buffer_offset}
      ) do
    extended_output = <<buffer::binary, 0::size(size * 8)>>

    {:reply, buffer_offset,
     %{state | buffer: extended_output, buffer_offset: buffer_offset + size}}
  end

  def handle_call(:input_size, _from, state = %{input: input}) do
    {:reply, byte_size(input), state}
  end

  def handle_call(:get_output, _from, state) do
    {:reply, Map.get(state, :output), state}
  end

  def handle_call(:get_error, _from, state) do
    {:reply, Map.get(state, :error), state}
  end

  def handle_call({:read, offset, length}, _from, state = %{buffer: buffer}) do
    {:reply, :erlang.binary_part(buffer, offset, length), state}
  end

  def handle_call(:clear, _, _state) do
    {:reply, :ok,
     %{
       input: <<>>,
       buffer: <<>>,
       buffer_offset: 0
     }}
  end
end
