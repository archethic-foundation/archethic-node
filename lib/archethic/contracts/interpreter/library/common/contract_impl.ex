defmodule Archethic.Contracts.Interpreter.Library.Common.ContractImpl do
  @moduledoc """
  this is not a behaviour because we define only few functions
  """

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract.Failure
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.WasmContract
  alias Archethic.Contracts.WasmModule
  alias Archethic.Contracts.WasmSpec

  use Archethic.Tag

  @tag [:io]
  @spec call_function(address :: binary(), function :: binary(), args :: list()) :: any()
  def call_function(address, function, args) do
    address = UtilsInterpreter.get_address(address, :call_function)

    unless is_binary(function),
      do:
        raise(Library.Error,
          message: "Contract.call_function must have binary function got #{inspect(function)}"
        )

    unless is_list(args),
      do:
        raise(Library.Error,
          message: "Contract.call_function must have list for args got #{inspect(args)}"
        )

    with {:ok, tx} <- Archethic.get_last_transaction(address),
         {:ok, genesis_address} <- Archethic.fetch_genesis_address(address),
         {:ok, contract} <- Contracts.from_transaction(tx),
         unspent_outputs = Archethic.get_unspent_outputs(genesis_address),
         {:ok, output, _logs} <-
           Contracts.execute_function(contract, function, args, unspent_outputs) do
      cast_function_output(function, contract, output)
    else
      {:error, reason} -> raise Library.Error, message: error_to_message(reason)
    end
  end

  defp error_to_message(%Failure{user_friendly_error: reason}) do
    "Contract.call_function failed with #{reason}"
  end

  defp error_to_message(reason) do
    "Contract.call_function failed with #{inspect(reason)}"
  end

  defp cast_function_output(function, %WasmContract{module: %WasmModule{spec: spec}}, output) do
    {:ok, function_spec} = WasmSpec.get_function_spec(spec, function)
    WasmSpec.cast_wasm_output(output, function_spec)
  end

  defp cast_function_output(_, _, output), do: output
end
