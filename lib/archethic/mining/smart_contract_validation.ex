defmodule Archethic.Mining.SmartContractValidation do
  @moduledoc """
  This module provides functions for validating smart contracts remotely.
  """

  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.TaskSupervisor

  @timeout 5_000

  @doc """
  Determine if the smart contracts conditions are valid according to the given transaction

  This function requests storage nodes of the contract address to execute the transaction validation and return assertion about the execution
  """
  @spec validate_contract_calls(
          recipients :: list(Recipient.t()),
          transaction :: Transaction.t(),
          validation_time :: DateTime.t()
        ) :: {true, fee :: non_neg_integer()} | {false, 0}
  def validate_contract_calls(
        recipients,
        transaction = %Transaction{},
        validation_time = %DateTime{}
      ) do
    TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      recipients,
      &request_contract_validation(&1, transaction, validation_time),
      timeout: @timeout + 500,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({true, 0}, fn
      {:ok, {_valid? = true, fee}}, {true, total_fee} -> {:cont, {true, total_fee + fee}}
      _, _ -> {:halt, {false, 0}}
    end)
  end

  defp request_contract_validation(
         recipient = %Recipient{address: address},
         transaction = %Transaction{},
         validation_time
       ) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    # We are strict on the results to achieve atomic commitment
    conflicts_resolver = fn results ->
      if Enum.any?(results, &(&1.valid? == false)) do
        %SmartContractCallValidation{valid?: false}
      else
        %SmartContractCallValidation{valid?: true}
      end
    end

    case P2P.quorum_read(
           storage_nodes,
           %ValidateSmartContractCall{
             recipient: recipient,
             transaction: transaction,
             inputs_before: validation_time
           },
           conflicts_resolver,
           @timeout
         ) do
      {:ok, %SmartContractCallValidation{valid?: valid?, fee: fee}} -> {valid?, fee}
      _ -> {false, 0}
    end
  end
end
