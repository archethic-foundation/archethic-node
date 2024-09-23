defmodule Archethic.Contracts.WasmModule do
  @moduledoc false
  alias Archethic.Contracts.WasmResult
  alias Archethic.Contracts.WasmSpec
  alias Archethic.Contracts.Wasm.ReadResult
  alias Archethic.Contracts.Wasm.UpdateResult
  alias Archethic.Contracts.WasmMemory
  alias Archethic.Contracts.WasmImports

  alias Archethic.TransactionChain.Transaction

  @reserved_functions ["onInit", "onUpgrade", "onInherit"]

  defstruct [:module, :store, :spec]

  @type t() :: %__MODULE__{
          module: Wasmex.Module.t(),
          store: Wasmex.StoreOrCaller.t(),
          spec: WasmSpec.t() | nil
        }

  @type execution_opts :: [
          now: DateTime.t(),
          state: map(),
          transaction: map(),
          balance: %{
            uco: pos_integer(),
            tokens:
              list(%{
                token_address: String.t(),
                token_id: pos_integer(),
                amount: pos_integer()
              })
          }
        ]

  @doc """
  Parse wasm module and perform some checks
  """
  @spec parse(bytes :: binary(), spec :: WasmSpec.t()) :: {:ok, t()} | {:error, any()}
  def parse(bytes, spec = %WasmSpec{}) when is_binary(bytes) do
    {:ok, engine} =
      Wasmex.Engine.new(Wasmex.EngineConfig.consume_fuel(%Wasmex.EngineConfig{}, true))

    {:ok, store} =
      Wasmex.Store.new(
        %Wasmex.StoreLimits{},
        engine
      )

    # TODO: define a minimum limit
    initial_gas_alloc = 100_000_000

    # Add fuel max limit
    Wasmex.StoreOrCaller.set_fuel(store, initial_gas_alloc)

    with {:ok, module} <- Wasmex.Module.compile(store, bytes),
         wrap_module = %__MODULE__{module: module, store: store},
         :ok <- check_module_imports(wrap_module),
         :ok <- check_module_exports(wrap_module),
         :ok <- check_spec_exports(wrap_module, spec) do
      {:ok, %{wrap_module | spec: spec}}
    end
  end

  defp check_module_imports(%__MODULE__{module: module}) do
    required_imports =
      [
        "archethic/env::alloc",
        "archethic/env::input_size",
        "archethic/env::load_u8",
        "archethic/env::set_error",
        "archethic/env::set_output",
        "archethic/env::store_u8"
      ]
      |> MapSet.new()

    allowed_imports =
      [
        "archethic/env::log",
        "archethic/env::jsonrpc"
      ]
      |> MapSet.new()

    imported_functions =
      module
      |> Wasmex.Module.imports()
      |> Enum.flat_map(fn {namespace, functions} ->
        Enum.map(functions, fn {fun_name, _} -> "#{namespace}::#{fun_name}" end)
      end)
      |> MapSet.new()

    if MapSet.subset?(required_imports, imported_functions) and
         MapSet.subset?(MapSet.difference(imported_functions, required_imports), allowed_imports) do
      :ok
    else
      {:error, "wasm's module imported functions are not the expected ones"}
    end
  end

  defp check_module_exports(%__MODULE__{module: module}) do
    exported_functions = exported_functions(module)

    if Enum.all?(exported_functions, &match?({_, {:fn, [], []}}, &1)) do
      :ok
    else
      {:error, "exported function shouldn't have input/output variables"}
    end
  end

  defp check_spec_exports(module, spec) do
    exported_functions = list_exported_functions_name(module)
    spec_functions = WasmSpec.function_names(spec)

    with :ok <- validate_existing_spec_functions(spec_functions, exported_functions) do
      validate_exported_functions_in_spec(spec_functions, exported_functions)
    end
  end

  defp validate_existing_spec_functions(spec_functions, exported_functions) do
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

  defp validate_exported_functions_in_spec(
         spec_functions,
         exported_functions
       ) do
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

  @spec list_exported_functions_name(t()) :: list(String.t())
  def list_exported_functions_name(%__MODULE__{module: module}) do
    module
    |> exported_functions()
    |> Enum.map(fn {name, _} -> name end)
  end

  defp exported_functions(module) do
    module
    |> Wasmex.Module.exports()
    |> Enum.filter(&match?({_, {:fn, _, _}}, &1))
    |> Enum.into(%{})
  end

  @spec execute(module :: t(), functionName :: binary(), opts :: execution_opts()) ::
          {:ok, ReadResult.t() | UpdateResult.t() | nil}
          | {:error, any()}
  def execute(%__MODULE__{module: module, store: store}, function_name, opts \\ [])
      when is_binary(function_name) do
    input =
      %{
        state: Keyword.get(opts, :state, %{}),
        transaction:
          opts
          |> Keyword.get(:transaction)
          |> cast_transaction(),
        arguments: Keyword.get(opts, :arguments),
        balance: Keyword.get(opts, :balance, %{uco: 0, tokens: []})
      }
      |> Jason.encode!()

    {:ok, io_mem_pid} = WasmMemory.start_link(Keyword.get(opts, :seed))
    WasmMemory.set_input(io_mem_pid, input)

    with {:ok, instance_pid} <-
           Wasmex.start_link(%{module: module, store: store, imports: imports(io_mem_pid)}),
         {:ok, _} <- Wasmex.call_function(instance_pid, function_name, []) do
      output = WasmMemory.get_output(io_mem_pid)
      cast_output(output)
    else
      {:error, _} = e ->
        case WasmMemory.get_error(io_mem_pid) do
          nil ->
            e

          custom_error ->
            {:error, Jason.decode!(custom_error)}
        end
    end
  end

  defp imports(io_mem_pid) do
    %{
      "archethic/env" => %{
        log:
          {:fn, [:i64, :i64], [],
           fn _context, offset, length -> WasmImports.log(offset, length, io_mem_pid) end},
        alloc:
          {:fn, [:i64], [:i64], fn _context, size -> WasmImports.alloc(size, io_mem_pid) end},
        input_size: {:fn, [], [:i64], fn _context -> WasmImports.input_size(io_mem_pid) end},
        load_u8:
          {:fn, [:i64], [:i32],
           fn _context, offset -> WasmImports.load_u8(offset, io_mem_pid) end},
        set_output:
          {:fn, [:i64, :i64], [],
           fn _context, offset, length -> WasmImports.set_output(offset, length, io_mem_pid) end},
        set_error:
          {:fn, [:i64, :i64], [],
           fn _context, offset, length -> WasmImports.set_error(offset, length, io_mem_pid) end},
        store_u8:
          {:fn, [:i64, :i32], [],
           fn _context, offset, value -> WasmImports.store_u8(offset, value, io_mem_pid) end},
        jsonrpc:
          {:fn, [:i64, :i64], [:i64],
           fn _context, offset, length -> WasmImports.jsonrpc(offset, length, io_mem_pid) end}
      }
    }
  end

  defp cast_output(nil), do: {:ok, nil}

  defp cast_output(output) do
    with {:ok, json} <- Jason.decode(output) do
      {:ok, WasmResult.cast(json)}
    end
  end

  defp cast_transaction(nil), do: nil

  defp cast_transaction(tx = %Transaction{}) do
    tx
    |> Transaction.to_map()
    |> wrap_binary()
  end

  defp wrap_binary(%{
         address: address,
         type: type,
         previous_public_key: previous_public_key,
         data: %{
           content: content,
           ledger: %{uco: %{transfers: uco_transfers}, token: %{transfers: token_transfers}},
           ownerships: ownerships,
           recipients: recipients
         }
       }) do
    %{
      address: %{hex: Base.encode16(address)},
      type: type,
      previous_public_key: %{hex: Base.encode16(previous_public_key)},
      data: %{
        content: content,
        # FIXME: find a better way to avoid timeout
        code: "",
        ledger: %{
          uco: %{
            transfers:
              Enum.map(uco_transfers, fn transfer ->
                Map.update!(transfer, :to, &%{hex: Base.encode16(&1)})
              end)
          },
          token: %{
            transfers:
              Enum.map(token_transfers, fn transfer ->
                transfer
                |> Map.update!(:to, &%{hex: Base.encode16(&1)})
                |> Map.update!(:token_address, &%{hex: Base.encode16(&1)})
              end)
          }
        },
        ownerships:
          Enum.map(ownerships, fn %{secret: secret, authorized_keys: authorized_keys} ->
            %{
              secret: %{hex: Base.encode16(secret)},
              authorized_keys:
                Enum.map(authorized_keys, fn {public_key, encrypted_key} ->
                  %{
                    public_key: %{hex: Base.encode16(public_key)},
                    encrypted_secret_key: %{hex: Base.encode16(encrypted_key)}
                  }
                end)
            }
          end)
      },
      recipients:
        Enum.map(recipients, fn recipient ->
          Map.update!(recipient, :address, &%{hex: Base.encode16(&1)})
        end)
    }
  end
end
