defmodule ArchethicWeb.API.JsonRPC.Method.CallContractFunction do
  @moduledoc """
  JsonRPC method to call a public function
  """

  alias ArchethicWeb.API.FunctionCallPayload
  alias ArchethicWeb.API.JsonRPC.Method
  alias ArchethicWeb.WebUtils

  @behaviour Method

  @spec validate_params(params :: map()) :: {:ok, params :: map()} | {:error, reasons :: list()}
  def validate_params(params) do
    case FunctionCallPayload.changeset(params) do
      %{valid?: true, changes: changed_params} ->
        {:ok, Map.update(changed_params, :args, [], fn val -> val end)}

      changeset ->
        reasons =
          Ecto.Changeset.traverse_errors(changeset, fn
            {message, [type: {:array, :any}, validation: :cast]} ->
              WebUtils.translate_error({message, [type: :array, validation: :cast]})

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
         {:ok, contract} <- Archethic.parse_contract(contract_tx),
         {:ok, result} <- Archethic.execute_function(contract, function_name, args) do
      {:ok, result}
    else
      {:error, reason} ->
        format_reason(reason, "#{function_name}/#{length(args)}")
    end
  end

  defp format_reason(:transaction_not_exists, _),
    do: {:error, :transaction_not_exists, "Contract transaction does not exist"}

  defp format_reason(:invalid_transaction, _),
    do: {:error, :invalid_transaction, "Contract transaction is invalid"}

  defp format_reason(:network_issue, _),
    do: {:error, :internal_error, "Cannot fetch contract transaction"}

  defp format_reason(:function_failure, function),
    do: {:error, :function_failure, "There was an error while executing the function", function}

  defp format_reason(:function_is_private, function),
    do: {:error, :function_is_private, "The function you are trying to call is private", function}

  defp format_reason(:function_does_not_exist, function),
    do:
      {:error, :function_does_not_exist, "The function you are trying to call does not exist",
       function}

  defp format_reason(reason, _) when is_binary(reason),
    do: {:error, :parsing_contract, "Error while parsing contract", reason}
end
