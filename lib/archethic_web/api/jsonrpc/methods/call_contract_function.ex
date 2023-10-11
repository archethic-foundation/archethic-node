defmodule ArchethicWeb.API.JsonRPC.Method.CallContractFunction do
  @moduledoc """
  JsonRPC method to call a public function
  """

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract.Failure
  alias Archethic.Contracts.Contract.PublicFunctionValue
  alias ArchethicWeb.API.FunctionCallPayload
  alias ArchethicWeb.API.JsonRPC.Method
  alias ArchethicWeb.WebUtils

  @behaviour Method

  @spec validate_params(params :: map()) :: {:ok, params :: map()} | {:error, reasons :: map()}
  def validate_params(params) do
    case FunctionCallPayload.changeset(params) do
      %{valid?: true, changes: changed_params} ->
        {:ok, Map.update(changed_params, :args, [], fn val -> val end)}

      changeset ->
        reasons =
          Ecto.Changeset.traverse_errors(changeset, fn
            change ->
              WebUtils.translate_error(change)
          end)

        {:error, reasons}
    end
  end

  @doc """
  Execute the function to evaluate function call with given args
  """
  @spec execute(params :: map()) ::
          {:ok, result :: any()}
          | {:error, reason :: atom(), message :: binary()}
          | {:error, reason :: atom(), message :: binary(), data :: any()}
  def execute(%{contract: contract_adress, function: function_name, args: args}) do
    with {:ok, contract_tx} <- Archethic.get_last_transaction(contract_adress),
         {:ok, contract} <- Contracts.from_transaction(contract_tx),
         %PublicFunctionValue{value: value} <-
           Contracts.execute_function(contract, function_name, args) do
      {:ok, value}
    else
      result_error = %Failure{} ->
        format_reason(result_error, "#{function_name}/#{length(args)}")

      {:error, reason} ->
        format_reason(reason)
    end
  end

  # Error must be static (jsonrpc spec), the dynamic part is in the 4th tuple position
  defp format_reason(
         %Failure{error: :function_failure, user_friendly_error: reason},
         _function
       ),
       do: {:error, :function_failure, "There was an error while executing the function", reason}

  defp format_reason(%Failure{error: error, user_friendly_error: reason}, function),
    do: {:error, error, reason, function}

  defp format_reason(:transaction_not_exists),
    do: {:error, :transaction_not_exists, "Contract transaction does not exist"}

  defp format_reason(:invalid_transaction),
    do: {:error, :invalid_transaction, "Contract transaction is invalid"}

  defp format_reason(:network_issue),
    do: {:error, :internal_error, "Cannot fetch contract transaction"}

  defp format_reason(reason) when is_binary(reason),
    do: {:error, :parsing_contract, "Error while parsing contract", reason}
end
