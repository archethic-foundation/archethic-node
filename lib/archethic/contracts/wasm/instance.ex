defmodule Archethic.Contracts.WasmInstance do
  use GenServer

  alias Archethic.Contracts.WasmModule
  alias Archethic.Contracts.WasmMemory
  alias Archethic.Contracts.WasmSpec
  alias Archethic.Contracts.Wasm.ReadResult

  @spec start_link(list()) :: GenServer.on_start()
  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  def execute(pid, function_name, arg, opts) do
    GenServer.call(pid, {:execute, function_name, arg, opts})
  end

  @spec spec(pid) :: WasmSpec.t()
  def spec(pid) do
    GenServer.call(pid, :spec)
  end

  def exported_functions(pid) do
    GenServer.call(pid, :exported_functions)
  end

  def init(arg) do
    bytes = Keyword.fetch!(arg, :bytes)
    transaction = Keyword.get(arg, :transaction)

    {:ok, io_mem_pid} = WasmMemory.start_link()
    {:ok, instance_pid} = WasmModule.get_instance(bytes, io_mem_pid)

    {:ok, %ReadResult{value: spec}} = WasmModule.execute(instance_pid, io_mem_pid, "spec")

    exported_functions = WasmModule.list_exported_functions(instance_pid)

    wasm_state =
      if "init" in exported_functions do
        {:ok, %ReadResult{value: initialized_state}} =
          WasmModule.execute(instance_pid, io_mem_pid, "init", transaction: transaction)

        initialized_state
      else
        %{}
      end

    {:ok,
     %{
       instance_pid: instance_pid,
       spec: WasmSpec.cast(spec),
       exported_functions: exported_functions,
       wasm_state: wasm_state,
       io_mem_pid: io_mem_pid
     }}
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

    WasmMemory.clear(io_mem_pid)

    {:reply, result, state}
  end
end
