defmodule Archethic.Contracts.WasmImports do
  @moduledoc """
  Handle all the import callback for the WebAssembly smart contract modules
  """

  alias Archethic.Contracts.WasmMemory
  alias Archethic.Contracts.Wasm.IO, as: WasmIO
  alias Archethic.Utils

  import Bitwise

  @doc """
  Log a message coming from WASM module
  """
  @spec log(offset :: pos_integer(), length :: pos_integer(), wasm_memory_pid :: pid()) :: :ok
  def log(offset, length, io_mem_pid) do
    log_msg = WasmMemory.read(io_mem_pid, offset, length)
    IO.puts("WASM log => #{log_msg}")
  end

  @doc """
  Store a byte coming from WASM module at the given offset into the WASM's shared memory
  """
  @spec store_u8(offset :: pos_integer(), value :: pos_integer(), wasm_memory_pid :: pid()) :: :ok
  def store_u8(offset, value, io_mem_pid), do: WasmMemory.store_u8(io_mem_pid, offset, value)

  @doc """
  Return a byte at the given offset from the WASM's shared memory
  """
  @spec load_u8(offset :: pos_integer(), wasm_memory_pid :: pid()) :: pos_integer()
  def load_u8(offset, io_mem_pid) do
    <<byte::8>> = WasmMemory.read(io_mem_pid, offset, 1)
    byte
  end

  @doc """
  Return the size of the of the initial loaded input registed in the WASM's shared memory
  """
  @spec input_size(wasm_memory_pid :: pid()) :: pos_integer()
  def input_size(io_mem_pid), do: WasmMemory.input_size(io_mem_pid)

  @doc """
  Extends the WASM's shared memory of the given size and return the offset of allocation
  """
  @spec alloc(size :: pos_integer(), wasm_memory_pid :: pid()) :: pos_integer()
  def alloc(size, io_mem_pid), do: WasmMemory.alloc(io_mem_pid, size)

  @doc """
  Set in the WASM's shared memory the WASM's output registed at the given memory location
  """
  @spec set_output(offset :: pos_integer(), length :: pos_integer(), wasm_memory_pid :: pid()) ::
          :ok
  def set_output(offset, length, io_mem_pid),
    do: WasmMemory.set_output(io_mem_pid, offset, length)

  @doc """
  Set in the WASM's shared memory the WASM's error registed at the given memory location
  """
  @spec set_error(offset :: pos_integer(), length :: pos_integer(), wasm_memory_pid :: pid()) ::
          :ok
  def set_error(offset, length, io_mem_pid),
    do: WasmMemory.set_error(io_mem_pid, offset, length)

  @doc """
  Query the node for some I/O function
  """
  def jsonrpc(offset, length, io_mem_pid) do
    contract_seed = WasmMemory.read_contract_seed(io_mem_pid)

    encoded_response =
      WasmMemory.read(io_mem_pid, offset, length)
      |> Jason.decode!()
      |> WasmIO.request(seed: contract_seed)
      |> Utils.bin2hex()
      |> Jason.encode!()

    size = byte_size(encoded_response)
    offset = WasmMemory.alloc(io_mem_pid, size)

    encoded_response
    |> :erlang.binary_to_list()
    |> Enum.with_index()
    |> Enum.each(fn {byte, i} ->
      WasmMemory.store_u8(io_mem_pid, offset + i, byte)
    end)

    combine_number(offset, size)
  end

  defp combine_number(a, b) do
    a <<< 32 ||| b
  end

  #  defp decombine_number(n) do
  #   a = n >>> 32
  #   u32_mask = 2 ** 32 - 1
  #   b = n &&& u32_mask
  #   {a, b}
  # end
end
