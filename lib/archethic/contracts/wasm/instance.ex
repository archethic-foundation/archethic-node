defmodule Archethic.Contracts.WasmInstance do
  @moduledoc false
  use GenServer

  @vsn 1

  alias Archethic.Contracts.WasmModule
  alias Archethic.Contracts.WasmMemory
  alias Archethic.Contracts.WasmSpec
  alias Archethic.Contracts.Wasm.ReadResult
  alias Archethic.Contracts.Wasm.UpdateResult

  @reserved_functions ["spec", "onInit", "onUpgrade"]

  @spec start_link(bytes: binary(), transaction: nil | map()) :: GenServer.on_start()
  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  @spec execute(pid(), String.t(), nil | map(), [state: map(), transaction: map()] | nil) ::
          {:ok, ReadResult.t() | UpdateResult.t()} | {:error, any()}
  def execute(pid, function_name, arg, opts) do
    GenServer.call(pid, {:execute, function_name, arg, opts})
  end

  @spec spec(pid) :: WasmSpec.t()
  def spec(pid) do
    GenServer.call(pid, :spec)
  end

  @spec exported_functions(pid) :: list(String.t())
  def exported_functions(pid) do
    GenServer.call(pid, :exported_functions)
  end

  def init(arg) do
    bytes = Keyword.fetch!(arg, :bytes)
    transaction = Keyword.get(arg, :transaction)

    {:ok, io_mem_pid} = WasmMemory.start_link()
    {:ok, instance_pid} = WasmModule.get_instance(bytes, io_mem_pid)

    {:ok, %ReadResult{value: spec}} = WasmModule.execute(instance_pid, io_mem_pid, "spec")
    wasm_spec = WasmSpec.cast(spec)

    exported_functions = WasmModule.list_exported_functions(instance_pid)

    with :ok <- validate_existing_spec_functions(wasm_spec, exported_functions),
         :ok <- validate_referenced_exported_functions(wasm_spec, exported_functions),
         {:ok, wasm_state} <-
           init_state(instance_pid, io_mem_pid, exported_functions, transaction: transaction) do
      {:ok,
       %{
         instance_pid: instance_pid,
         spec: wasm_spec,
         exported_functions: exported_functions,
         wasm_state: wasm_state,
         io_mem_pid: io_mem_pid
       }}
    end
  end

  defp init_state(instance_pid, io_mem_pid, exported_functions, opts) do
    if "init" in exported_functions do
      case WasmModule.execute(instance_pid, io_mem_pid, "onInit", opts) do
        {:ok, %ReadResult{value: initialized_state}} ->
          {:ok, initialized_state}

        {:error, _} = e ->
          e
      end
    else
      {:ok, %{}}
    end
  end

  defp validate_existing_spec_functions(
         %WasmSpec{triggers: triggers, public_functions: public_functions},
         exported_functions
       ) do
    spec_functions = Enum.map(triggers, & &1.function_name) ++ public_functions

    case spec_functions
         |> MapSet.new()
         |> MapSet.difference(MapSet.new(exported_functions))
         |> MapSet.to_list() do
      [] ->
        :ok

      difference ->
        {:error,
         "Contract doesn't have functions: #{Enum.join(difference, ",")} as mentioned in the spec"}
    end
  end

  defp validate_referenced_exported_functions(
         %WasmSpec{triggers: triggers, public_functions: public_functions},
         exported_functions
       ) do
    spec_functions = Enum.map(triggers, & &1.function_name) ++ public_functions

    case exported_functions
         |> MapSet.new()
         |> MapSet.difference(MapSet.new(spec_functions))
         |> MapSet.reject(&(&1 in @reserved_functions))
         |> MapSet.to_list() do
      [] ->
        :ok

      difference ->
        {:error, "Spec doesn't reference the functions: #{Enum.join(difference, ",")}"}
    end
  end

  def handle_call(:spec, _from, state = %{spec: spec}) do
    {:reply, spec, state}
  end

  def handle_call(:exported_functions, _from, state = %{exported_functions: exported_functions}) do
    {:reply, exported_functions, state}
  end

  def handle_call(
        {:execute, function_name, arg, opts},
        _,
        state = %{instance_pid: instance_pid, wasm_state: wasm_state, io_mem_pid: io_mem_pid}
      ) do
    result =
      WasmModule.execute(
        instance_pid,
        io_mem_pid,
        function_name,
        Keyword.merge([state: wasm_state, arguments: arg], opts)
      )

    {:reply, result, state}
  end
end
