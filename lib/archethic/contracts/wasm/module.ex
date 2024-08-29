defmodule Archethic.Contracts.WasmModule do
  @moduledoc false
  alias Archethic.Contracts.WasmResult
  alias Archethic.Contracts.WasmSpec
  alias Archethic.Contracts.Wasm.ReadResult
  alias Archethic.Contracts.Wasm.UpdateResult
  alias Archethic.Contracts.WasmMemory

  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils

  @type opts :: [
          now: DateTime.t(),
          state: map(),
          transaction: map(),
          fuel: pos_integer()
        ]

  @spec get_instance(bytes :: binary(), io_mem_pid :: pid(), opts()) :: GenServer.on_start()
  def get_instance(bytes, io_mem_pid, opts \\ []) do
    engine_config =
      %Wasmex.EngineConfig{}
      |> Wasmex.EngineConfig.consume_fuel(true)

    {:ok, engine} = Wasmex.Engine.new(engine_config)

    {:ok, store} =
      Wasmex.Store.new(
        %Wasmex.StoreLimits{},
        engine
      )

    # TODO: define a minimum limit
    initial_gas_alloc = Keyword.get(opts, :fuel, 100_000_000)

    # # Add fuel max limit
    Wasmex.StoreOrCaller.add_fuel(store, initial_gas_alloc)

    {:ok, module} = Wasmex.Module.compile(store, bytes)

    Wasmex.start_link(%{store: store, module: module, imports: imports(io_mem_pid)})
  end

  @spec list_exported_functions(instance_pid :: pid()) :: list(String.t())
  def list_exported_functions(instance_pid) do
    {:ok, module} = Wasmex.module(instance_pid)

    module
    |> Wasmex.Module.exports()
    |> Enum.filter(&match?({_, {:fn, _, _}}, &1))
    |> Enum.map(fn {name, _} -> name end)
  end

  @spec execute(instance :: pid(), io_mem_pid :: pid(), functionName :: String.t(), opts()) ::
          {:ok, ReadResult.t() | UpdateResult.t()}
          | {:ok, WasmSpec.t()}
          | {:error, :function_not_exists}
          | {:error, {:invalid_output, nil}}
          | {:error, any()}
  def execute(instance_pid, io_mem_pid, function_name, opts \\ []) do
    input =
      %{
        state: Keyword.get(opts, :state, %{}),
        transaction:
          opts
          |> Keyword.get(:transaction)
          |> cast_transaction(),
        arguments: Keyword.get(opts, :arguments)
      }
      |> Jason.encode!()

    WasmMemory.set_input(io_mem_pid, input)

    with :ok <- check_function_existance(instance_pid, function_name),
         {:ok, response} <-
           Wasmex.call_function(instance_pid, function_name, []) do
      case response do
        [code] when code > 0 ->
          {:error, "Unknown error"}

        _ ->
          output = WasmMemory.get_output(io_mem_pid)
          cast_output(output)
      end
    else
      {:error, e} ->
        case WasmMemory.get_error(io_mem_pid) do
          nil ->
            {:error, e}

          custom_error ->
            {:error, custom_error}
        end
    end
  end

  defp imports(io_mem_pid) do
    log = fn _, offset, length ->
      log_msg = WasmMemory.read(io_mem_pid, offset, length)
      IO.puts("WASM log => #{log_msg}")
    end

    store_u8 = fn _, offset, value ->
      WasmMemory.store_u8(io_mem_pid, offset, value)
    end

    input_load_u8 = fn _, offset ->
      WasmMemory.input_load_u8(io_mem_pid, offset)
    end

    input_size = fn _ -> WasmMemory.input_size(io_mem_pid) end

    alloc = fn _, size ->
      WasmMemory.alloc(io_mem_pid, size)
    end

    set_output = fn _, offset, length ->
      WasmMemory.set_output(io_mem_pid, offset, length)
    end

    set_error = fn _, offset, length -> WasmMemory.set_error(io_mem_pid, offset, length) end

    %{
      "archethic/env" => %{
        log: {:fn, [:i64, :i64], [], log},
        alloc: {:fn, [:i64], [:i64], alloc},
        store_u8: {:fn, [:i64, :i32], [], store_u8},
        input_load_u8: {:fn, [:i64], [:i32], input_load_u8},
        input_size: {:fn, [], [:i64], input_size},
        set_output: {:fn, [:i64, :i64], [], set_output},
        set_error: {:fn, [:i64, :i64], [], set_error}
      }
    }
  end

  defp check_function_existance(instance_pid, function_name) do
    if Wasmex.function_exists(instance_pid, function_name) do
      :ok
    else
      {:error, :function_not_exists}
    end
  end

  defp cast_output(nil), do: {:error, {:invalid_output, nil}}

  defp cast_output(output) do
    with {:ok, json} <- Jason.decode(output) do
      {:ok, WasmResult.cast(json)}
    end
  end

  defp cast_transaction(nil), do: nil

  defp cast_transaction(tx) when is_map(tx) do
    tx
    |> Transaction.to_map()
    # FIXME: find a better way to avoid timeout based on the uncompressed code
    |> put_in([:data, :code], "")
    |> Utils.bin2hex()
  end
end
