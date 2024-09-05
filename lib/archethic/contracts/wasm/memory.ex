defmodule Archethic.Contracts.WasmMemory do
  @moduledoc """
  Represents the WASM's shared memory used to perform I/O for the WebAssembly module
  """

  use GenServer

  @vsn 1

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  @doc """
  Set the input in the shared memory to be retrieved later
  """
  @spec set_input(GenServer.server(), binary()) :: :ok
  def set_input(server, input) do
    GenServer.cast(server, {:set_input, input})
  end

  @doc """
  Returns the size of the input stored in the memory state
  """
  @spec input_size(GenServer.server()) :: pos_integer()
  def input_size(server) do
    GenServer.call(server, :input_size)
  end

  @doc """
  Extends the shared memory and return the offset of the allocation
  """
  @spec alloc(GenServer.server(), size :: pos_integer()) :: offset :: pos_integer()
  def alloc(server, size) do
    GenServer.call(server, {:alloc, size})
  end

  @doc """
  Store the data in shared memory at the offset's position
  """
  @spec store_u8(GenServer.server(), offset :: pos_integer(), data :: pos_integer()) :: :ok
  def store_u8(server, offset, data) do
    GenServer.cast(server, {:store_u8, offset, data})
  end

  @doc """
  Set the output read from the offset of the shared memory to be used later
  """
  @spec set_output(GenServer.server(), offset :: pos_integer(), length :: pos_integer()) :: :ok
  def set_output(server, offset, length) do
    GenServer.cast(server, {:set_output, offset, length})
  end

  @doc """
  Retrieve the output registed by `set_output/3`
  """
  @spec get_output(GenServer.server()) :: binary() | nil
  def get_output(server) do
    GenServer.call(server, :get_output)
  end

  @doc """
  Set the error read from the offset of the shared memory to be used later
  """
  @spec set_error(GenServer.server(), offset :: pos_integer(), length :: pos_integer()) :: :ok
  def set_error(server, offset, length) do
    GenServer.cast(server, {:set_error, offset, length})
  end

  @doc """
  Retrieve the error registed by `set_output/3`
  """
  @spec get_error(GenServer.server()) :: binary() | nil
  def get_error(server) do
    GenServer.call(server, :get_error)
  end

  @doc """
  Read the memory at the given offset for the given length
  """
  @spec read(GenServer.server(), offset :: pos_integer(), length :: pos_integer()) :: binary()
  def read(server, offset, length) do
    GenServer.call(server, {:read, offset, length})
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
    {:noreply, Map.put(state, :error, err_payload)}
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
end
