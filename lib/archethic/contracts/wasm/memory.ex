defmodule Archethic.Contracts.WasmMemory do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def set_input(pid, input) do
    GenServer.cast(pid, {:set_input, input})
  end

  def input_size(pid) do
    GenServer.call(pid, :input_size)
  end

  def input_load_u8(pid, offset) do
    GenServer.call(pid, {:input_load_u8, offset})
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
       output_buffer: <<>>,
       output_buffer_offset: 0
     }}
  end

  def handle_cast({:set_input, input}, state) do
    {:noreply, %{state | input: input}}
  end

  def handle_cast({:store_u8, 0, data}, state = %{output_buffer: <<_::8, remaining::binary>>}) do
    {:noreply, %{state | output_buffer: <<data::8, remaining::binary>>}}
  end

  def handle_cast(
        {:store_u8, offset, data},
        state = %{output_buffer: output_buffer}
      ) do
    offset_size = offset * 8
    <<prev::size(offset_size), _::8, remaining::binary>> = output_buffer

    {:noreply,
     %{
       state
       | output_buffer: <<prev::size(offset_size), data::8, remaining::binary>>
     }}
  end

  def handle_cast({:set_output, offset, length}, state = %{output_buffer: output_buffer}) do
    {:noreply, Map.put(state, :output, :erlang.binary_part(output_buffer, offset, length))}
  end

  def handle_cast({:set_error, offset, length}, state = %{output_buffer: output_buffer}) do
    errorPayload = :erlang.binary_part(output_buffer, offset, length)
    err = Jason.decode!(errorPayload)
    {:noreply, Map.put(state, :error, err)}
  end

  def handle_call(
        {:alloc, size},
        _from,
        state = %{output_buffer: output_buffer, output_buffer_offset: output_buffer_offset}
      ) do
    extended_output = <<output_buffer::binary, 0::size(size * 8)>>

    {:reply, output_buffer_offset,
     %{state | output_buffer: extended_output, output_buffer_offset: output_buffer_offset + size}}
  end

  def handle_call({:input_load_u8, offset}, _from, state = %{input: input}) do
    <<byte::8>> = :erlang.binary_part(input, offset, 1)
    {:reply, byte, state}
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

  def handle_call({:read, offset, length}, _from, state = %{output_buffer: output_buffer}) do
    {:reply, :erlang.binary_part(output_buffer, offset, length), state}
  end

  def handle_call(:clear, _, _state) do
    {:reply, :ok,
     %{
       input: <<>>,
       output_buffer: <<>>,
       output_buffer_offset: 0
     }}
  end
end
