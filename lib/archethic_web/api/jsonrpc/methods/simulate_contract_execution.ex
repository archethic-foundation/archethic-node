defmodule ArchethicWeb.API.JsonRPC.Method.SimulateContractExecution do
  @moduledoc """
  JsonRPC method to simulate the execution of a contract added in the recipients field of a transaction
  """

  alias Archethic.TaskSupervisor

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias ArchethicWeb.API.JsonRPC.Method
  alias ArchethicWeb.API.JsonRPC.Error
  alias ArchethicWeb.API.TransactionPayload

  alias ArchethicWeb.WebUtils

  @behaviour Method

  @doc """
  Validate parameter to match the expected JSON pattern
  """
  @spec validate_params(param :: map()) ::
          {:ok, params :: Transaction.t()} | {:error, reasons :: map()}
  def validate_params(%{"transaction" => transaction_params}) do
    case TransactionPayload.changeset(transaction_params) do
      {:ok, changeset = %{valid?: true}} ->
        tx = changeset |> TransactionPayload.to_map() |> Transaction.cast()
        {:ok, tx}

      {:ok, changeset} ->
        reasons = Ecto.Changeset.traverse_errors(changeset, &WebUtils.translate_error/1)
        {:error, reasons}

      :error ->
        {:error, %{transaction: ["must be an object"]}}
    end
  end

  def validate_params(_), do: {:error, %{transaction: ["is required"]}}

  @doc """
  Execute the function to send a new tranaction in the network
  """
  @spec execute(params :: Transaction.t()) :: {:ok, result :: list()}
  def execute(tx = %Transaction{data: %TransactionData{recipients: recipients}}) do
    # We add a dummy ValidationStamp to the transaction
    # because the Interpreter requires a validated transaction
    trigger_tx = %Transaction{tx | validation_stamp: ValidationStamp.generate_dummy()}

    results =
      Task.Supervisor.async_stream_nolink(
        TaskSupervisor,
        recipients,
        &fetch_recipient_tx_and_simulate(&1, trigger_tx),
        on_timeout: :kill_task
      )
      |> Stream.zip(recipients)
      |> Enum.map(fn
        {{:ok, :ok}, recipient} ->
          create_valid_response(recipient)

        {{:ok, {:error, reason}}, recipient} ->
          create_error_response(recipient, reason)

        {{:exit, reason}, recipient} ->
          create_error_response(recipient, reason)
      end)

    case results do
      [] -> {:error, :no_recipients, "There are no recipients in the transaction"}
      _ -> {:ok, results}
    end
  end

  defp fetch_recipient_tx_and_simulate(
         recipient = %Recipient{address: recipient_address},
         trigger_tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}}
       ) do
    with {:ok, contract_tx} <-
           Archethic.get_last_transaction(recipient_address),
         {:ok, contract} <- Contracts.from_transaction(contract_tx),
         trigger <- Contract.get_trigger_for_recipient(recipient),
         :ok <- validate_contract_condition(trigger, contract, trigger_tx, recipient, timestamp),
         {:ok, next_tx} <- Contracts.execute_trigger(trigger, contract, trigger_tx, recipient) do
      validate_contract_condition(:inherit, contract, next_tx, nil, timestamp)
    end
  end

  defp create_valid_response(%Recipient{address: recipient_address}) do
    %{"recipient_address" => Base.encode16(recipient_address), "valid" => true}
  end

  defp create_error_response(%Recipient{address: recipient_address}, reason) do
    %{
      "recipient_address" => Base.encode16(recipient_address),
      "valid" => false,
      "error" => format_reason(reason) |> Error.get_error()
    }
  end

  defp format_reason(:transaction_not_exists),
    do: {:custom_error, :transaction_not_exists, "Contract transaction does not exist"}

  defp format_reason(:invalid_transaction),
    do: {:custom_error, :invalid_transaction, "Contract transaction is invalid"}

  defp format_reason(:network_issue),
    do: {:internal_error, "Cannot fetch contract transaction"}

  defp format_reason(:contract_failure),
    do: {:custom_error, :contract_failure, "Contract execution encountered an error"}

  defp format_reason(:invalid_triggers_execution),
    do:
      {:custom_error, :invalid_triggers_execution,
       "Contract does not contain a trigger transaction"}

  defp format_reason(:invalid_transaction_constraints),
    do:
      {:custom_error, :invalid_transaction_constraints,
       "Trigger transactin failed to pass transaction constraints"}

  defp format_reason(:invalid_inherit_constraints),
    do:
      {:custom_error, :invalid_inherit_constraints,
       "Contract next transaction failed to pass inherit constraints"}

  defp format_reason(:timeout),
    do: {:internal_error, "Timeout while simulating contract execution"}

  defp format_reason(reason) when is_binary(reason),
    do: {:custom_error, :parsing_contract, "Error while parsing contract", reason}

  defp format_reason(_), do: {:internal_error, "Unknown error"}

  defp validate_contract_condition(condition_type, contract, tx, recipient, timestamp) do
    if Contracts.valid_condition?(condition_type, contract, tx, recipient, timestamp) do
      :ok
    else
      case condition_type do
        :inherit -> {:error, :invalid_inherit_constraints}
        {:transaction, _, _} -> {:error, :invalid_transaction_constraints}
      end
    end
  end
end
