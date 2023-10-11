defmodule Archethic.Contracts.Interpreter.Library.Common.ContractImpl do
  @moduledoc """
  this is not a behaviour because we define only few functions
  """

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract.Failure
  alias Archethic.Contracts.Contract.PublicFunctionValue
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter
  alias Archethic.Contracts.Interpreter.Library

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
         {:ok, contract} <- Contracts.from_transaction(tx),
         %PublicFunctionValue{value: value} <-
           Contracts.execute_function(contract, function, args) do
      value
    else
      err -> raise Library.Error, message: error_to_message(err)
    end
  end

  defp error_to_message(%Failure{user_friendly_error: reason}) do
    "Contract.call_function failed with #{reason}"
  end

  defp error_to_message({:error, reason}) do
    "Contract.call_function failed with #{inspect(reason)}"
  end
end
