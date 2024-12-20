defmodule Archethic.Contracts.WasmSpec do
  @moduledoc """
  Represents a WASM Smart Contract Specification
  """

  alias __MODULE__.Function
  alias __MODULE__.Trigger
  alias __MODULE__.UpgradeOpts
  alias Archethic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          version: pos_integer(),
          triggers: list(Trigger.t()),
          public_functions: list(Function.t()),
          upgrade_opts: nil | UpgradeOpts.t()
        }
  defstruct [:version, triggers: [], public_functions: [], upgrade_opts: nil]

  def from_manifest(
        manifest = %{
          "abi" => %{
            "functions" => functions
          }
        }
      ) do
    version = Map.get(manifest, "version", 1)
    upgrade_opts = Map.get(manifest, "upgradeOpts")

    Enum.reduce(
      functions,
      %__MODULE__{
        version: version,
        upgrade_opts: UpgradeOpts.cast(upgrade_opts),
        triggers: [],
        public_functions: []
      },
      fn
        {name, function_abi = %{"type" => "action"}}, acc ->
          Map.update!(acc, :triggers, &[Trigger.cast(name, function_abi) | &1])

        {name, function_abi = %{"type" => "publicFunction"}}, acc ->
          Map.update!(acc, :public_functions, &[Function.cast(name, function_abi) | &1])
      end
    )
  end

  @doc """
  Return the function exposed in the spec
  """
  @spec function_names(t()) :: list(String.t())
  def function_names(%__MODULE__{triggers: triggers, public_functions: public_functions}) do
    Enum.map(triggers, & &1.name) ++ Enum.map(public_functions, & &1.name)
  end

  @spec cast_wasm_input(any(), any()) :: {:ok, any()} | {:error, :invalid_input_type}
  def cast_wasm_input(nil, _), do: {:ok, nil}

  def cast_wasm_input(value, input)
      when input in ["Address", "Hex", "PublicKey"] and is_binary(value) do
    case Base.decode16(value, case: :mixed) do
      {:ok, _} -> {:ok, %{"hex" => value}}
      _ -> {:error, :invalid_hex}
    end
  end

  def cast_wasm_input(value, input)
      when input in ["i8"] and is_integer(value) and value > -128 and value < 127,
      do: {:ok, value}

  def cast_wasm_input(value, input)
      when input in ["u8"] and is_integer(value) and value > 0 and value < 256,
      do: {:ok, value}

  def cast_wasm_input(value, input)
      when input in ["i16"] and is_integer(value) and value > -32_768 and value < 32_767,
      do: value

  def cast_wasm_input(value, input)
      when input in ["u16"] and is_integer(value) and value > 0 and value < 65535,
      do: {:ok, value}

  def cast_wasm_input(value, input)
      when input in ["i32"] and is_integer(value) and value > -2_147_483_648 and
             value < 2_147_483_647,
      do: value

  def cast_wasm_input(value, input)
      when input in ["u32"] and is_integer(value) and value > 0 and value < 4_294_967_295,
      do: {:ok, value}

  def cast_wasm_input(value, input)
      when input in ["i64"] and is_integer(value) and value > -9_223_372_036_854_775_808 and
             value < 9_223_372_036_854_775_807,
      do: {:ok, value}

  def cast_wasm_input(value, input)
      when input in ["u64"] and is_integer(value) and value > 0 and
             value < 18_446_744_073_709_551_615,
      do: {:ok, value}

  def cast_wasm_input(value, "string") when is_binary(value), do: {:ok, value}
  def cast_wasm_input(value, "map") when is_map(value), do: {:ok, value}

  def cast_wasm_input(value, [input]) when is_list(value) do
    %{value: value, error: error} =
      Enum.reduce_while(value, %{value: [], error: nil}, fn val, acc ->
        case cast_wasm_input(val, input) do
          {:ok, value} ->
            {:cont, Map.update!(acc, :value, &(&1 ++ [value]))}

          {:error, reason} ->
            {:halt, %{acc | error: reason}}
        end
      end)

    case error do
      nil -> {:ok, value}
      reason -> {:error, reason}
    end
  end

  def cast_wasm_input(value, input) when is_map(value) do
    %{value: value, error: error} =
      Enum.reduce_while(value, %{value: %{}, error: nil}, fn {k, v}, acc ->
        case cast_wasm_input(v, Map.get(input, k)) do
          {:ok, value} ->
            {:cont, put_in(acc, [:value, k], value)}

          {:error, reason} ->
            {:halt, %{acc | error: reason}}
        end
      end)

    case error do
      nil -> {:ok, value}
      reason -> {:error, reason}
    end
  end

  def cast_wasm_input(_val, _type) do
    {:error, :invalid_input_type}
  end

  @spec cast_wasm_output(result_value :: any(), manifest_output_type :: any()) :: any()
  def cast_wasm_output(%{"hex" => value}, output)
      when output in ["Address", "Hex", "PublicKey"] do
    Base.decode16!(value, case: :mixed)
  end

  def cast_wasm_output(
        %{
          "address" => %{"hex" => address},
          "type" => type,
          "data" => %{
            "content" => content,
            "ledger" => %{
              "uco" => %{"transfers" => uco_transfers},
              "token" => %{"transfers" => token_transfers}
            },
            "recipients" => recipients
            # "ownerships" => ownerships
          }
        },
        "Transaction"
      ) do
    %{
      address: Base.decode16!(address, case: :mixed),
      type: type,
      data: %{
        content: content,
        ledger: %{
          uco: %{
            transfers:
              Enum.map(
                uco_transfers,
                fn %{"to" => %{"hex" => to}, "amount" => amount} ->
                  %{to: Base.decode16!(to, case: :mixed), amount: amount}
                end
              )
          },
          token: %{
            transfers:
              Enum.map(
                token_transfers,
                fn transfer = %{
                     "to" => %{"hex" => to},
                     "amount" => amount,
                     "token_address" => %{"hex" => token_address}
                   } ->
                  %{
                    to: Base.decode16!(to, case: :mixed),
                    amount: amount,
                    token_address: Base.decode16!(token_address, case: :mixed),
                    token_id: Map.get(transfer, "token_id", 0)
                  }
                end
              )
          }
        },
        recipients:
          Enum.map(recipients, fn %{
                                    "address" => %{"hex" => address},
                                    "action" => action,
                                    "args" => args
                                  } ->
            %{address: Base.decode16!(address, case: :mixed), action: action, args: args}
          end)
      }
    }
    |> Transaction.cast()
  end

  def cast_wasm_output(map, output) when is_map(map) do
    Enum.map(map, fn
      {k, _v = %{"hex" => value}} ->
        case Map.get(output, k) do
          type when type in ["Address", "PublicKey", "Hex"] ->
            {k, Base.decode16!(value, case: :mixed)}

          type ->
            {k, cast_wasm_output(value, type)}
        end

      {k, v} ->
        case Map.get(output, k) do
          nil -> {k, v}
          output -> {k, cast_wasm_output(v, output)}
        end
    end)
    |> Enum.into(%{})
  end

  def cast_wasm_output(list, [output]) when is_list(list),
    do: Enum.map(list, &cast_wasm_output(&1, output))

  def cast_wasm_output(value, _output), do: value
end
