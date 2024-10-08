defmodule ArchethicWeb.API.JsonRPC.Method.CallContractFunction do
  @moduledoc """
  JsonRPC method to call a public function
  """

  alias Archethic.Contracts.WasmContract
  alias Archethic.Contracts

  alias Archethic.Contracts.Contract.Failure
  alias ArchethicWeb.API.FunctionCallPayload
  alias ArchethicWeb.API.JsonRPC.Method
  alias ArchethicWeb.WebUtils

  @behaviour Method

  @spec validate_params(params :: map()) :: {:ok, params :: map()} | {:error, reasons :: map()}
  def validate_params(params) do
    case FunctionCallPayload.changeset(params) do
      %{valid?: true, changes: changed_params} ->
        changed_params =
          changed_params |> Map.update(:args, [], & &1) |> Map.update(:resolve_last, true, & &1)

        {:ok, changed_params}

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
  def execute(%{
        contract: contract_address,
        function: function_name,
        args: args,
        resolve_last: resolve?
      }) do
    with {:ok, contract_tx} <- get_transaction(contract_address, resolve?),
         {:ok, contract} <- Contracts.from_transaction(contract_tx),
         {:ok, inputs} <- get_inputs(contract_address, resolve?),
         {:ok, value, _logs} <-
           Contracts.execute_function(
             contract,
             function_name,
             format_args(contract, args),
             inputs
           ) do
      {:ok, value}
    else
      {:error, reason} ->
        format_reason(reason)
    end
  end

  defp format_args(%WasmContract{}, []), do: %{}
  defp format_args(_, args), do: args

  defp get_transaction(contract_address, _resolve? = true),
    do: Archethic.get_last_transaction(contract_address)

  defp get_transaction(contract_address, _resolve? = false),
    do: Archethic.search_transaction(contract_address)

  defp get_inputs(contract_address, _resolve? = true) do
    case Archethic.fetch_genesis_address(contract_address) do
      {:ok, genesis_address} -> {:ok, Archethic.get_unspent_outputs(genesis_address)}
      {:error, _} = e -> e
    end
  end

  defp get_inputs(contract_address, _resolve? = false) do
    {:ok, Archethic.get_transaction_inputs(contract_address)}
  end

  # Error must be static (jsonrpc spec), the dynamic part is in the 4th tuple position
  defp format_reason(%Failure{error: :contract_throw, data: data}) do
    data = if match?({:ok, _}, Jason.encode(data)), do: data, else: nil

    {:error, :contract_throw, "Function execution returned an error", data}
  end

  defp format_reason(%Failure{error: error, user_friendly_error: reason}),
    do: {:error, error, "There was an error while executing the function", reason}

  defp format_reason(:transaction_not_exists),
    do: {:error, :transaction_not_exists, "Contract transaction does not exist"}

  defp format_reason(:invalid_transaction),
    do: {:error, :invalid_transaction, "Contract transaction is invalid"}

  defp format_reason(:network_issue),
    do: {:error, :internal_error, "Cannot fetch contract transaction"}

  defp format_reason(reason) when is_binary(reason),
    do: {:error, :parsing_contract, "Error while parsing contract", reason}
end
