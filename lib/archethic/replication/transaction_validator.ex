defmodule Archethic.Replication.TransactionValidator do
  @moduledoc false

  alias Archethic.Bootstrap
  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Crypto
  alias Archethic.DB
  alias Archethic.Election
  alias Archethic.Mining
  alias Archethic.Mining.SmartContractValidation
  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  require Logger

  @typedoc """
  Represents the different errors during the validation for the transaction replication
  """
  @type error ::
          :invalid_atomic_commitment
          | :invalid_node_election
          | :invalid_proof_of_work
          | :invalid_transaction_fee
          | :invalid_transaction_movements
          | :insufficient_funds
          | :invalid_chain
          | :invalid_transaction_with_inconsistencies
          | :invalid_inherit_constraints
          | :invalid_unspent_outputs
          | {:invalid_recipients_execution, String.t(), any()}
          | :invalid_contract_execution
          | :invalid_contract_context_inputs

  @doc """
  Validate transaction with context

  This function is called by the chain replication nodes
  """
  @spec validate(
          tx :: Transaction.t(),
          previous_transaction :: Transaction.t() | nil,
          genesis_address :: Crypto.prepended_hash(),
          inputs :: list(VersionedUnspentOutput.t()),
          contract_context :: nil | Contract.Context.t()
        ) :: :ok | {:error, error()}
  def validate(
        tx = %Transaction{},
        previous_transaction,
        genesis_address,
        inputs,
        contract_context
      ) do
    with :ok <-
           valid_transaction(tx, previous_transaction, genesis_address, inputs, contract_context),
         :ok <- validate_inheritance(previous_transaction, tx, contract_context, inputs) do
      validate_chain(tx, previous_transaction)
    end
  end

  # it is fine to assume validation_stamp is valid because this step is done after validate_validation_stamp
  defp validate_inheritance(
         prev_tx = %Transaction{data: %TransactionData{code: code}},
         next_tx = %Transaction{
           validation_stamp: %ValidationStamp{
             timestamp: validation_time
           }
         },
         contract_context,
         validation_inputs
       )
       when code != "" do
    contract_inputs =
      case contract_context do
        nil ->
          validation_inputs

        %Contract.Context{inputs: inputs} ->
          inputs
      end

    case Contracts.execute_condition(
           :inherit,
           Contract.from_transaction!(prev_tx),
           next_tx,
           nil,
           validation_time,
           VersionedUnspentOutput.unwrap_unspent_outputs(contract_inputs)
         ) do
      {:ok, _logs} ->
        :ok

      _ ->
        # TODO: propagate error, or subject
        {:error, :invalid_inherit_constraints}
    end
  end

  # handle case:
  # - no prev tx
  # - prev tx has no inherit condition
  defp validate_inheritance(_prev_tx, _next_tx, _contract_context, _inputs), do: :ok

  defp validate_chain(tx, prev_tx) do
    if TransactionChain.valid?([tx, prev_tx]) do
      :ok
    else
      {:error, :invalid_chain}
    end
  end

  @doc """
  Validate transaction only (without chain integrity or unspent outputs)

  This function called by the replication nodes which are involved in the chain storage
  """
  @spec validate(Transaction.t()) :: :ok | {:error, error()}
  def validate(tx = %Transaction{}) do
    with :ok <- validate_consensus(tx),
         :ok <- validate_validation_stamp(tx) do
      :ok
    else
      {:error, _} = e ->
        # TODO: start malicious detection
        e
    end
  end

  defp valid_transaction(tx, prev_tx, genesis_address, inputs, contract_context)
       when is_list(inputs) do
    with :ok <- validate_consensus(tx),
         :ok <- validate_validation_stamp(tx),
         {:ok, encoded_state} <-
           validate_contract_execution(contract_context, prev_tx, genesis_address, tx, inputs),
         :ok <- validate_inputs(tx, inputs, encoded_state, contract_context),
         {:ok, contract_recipient_fees} <- validate_contract_recipients(tx),
         :ok <-
           validate_transaction_fee(tx, contract_recipient_fees, contract_context, encoded_state) do
      :ok
    else
      {:error, _} = e ->
        # TODO: start malicious detection
        e
    end
  end

  defp validate_contract_recipients(%Transaction{
         validation_stamp: %ValidationStamp{recipients: []}
       }) do
    {:ok, 0}
  end

  defp validate_contract_recipients(
         tx = %Transaction{
           data: %TransactionData{recipients: recipients},
           validation_stamp: %ValidationStamp{
             recipients: resolved_recipients,
             timestamp: timestamp
           }
         }
       ) do
    res =
      recipients
      |> Enum.zip(resolved_recipients)
      |> Enum.map(fn {recipient, resolved_address} ->
        %Recipient{recipient | address: resolved_address}
      end)
      |> SmartContractValidation.validate_contract_calls(tx, timestamp)

    case res do
      {:ok, fees} -> {:ok, fees}
      {:error, message, data} -> {:error, {:invalid_recipients_execution, message, data}}
    end
  end

  defp validate_contract_execution(contract_context, prev_tx, genesis_address, tx, inputs) do
    if Contract.Context.valid_inputs?(contract_context, inputs) do
      case SmartContractValidation.valid_contract_execution?(
             contract_context,
             prev_tx,
             genesis_address,
             tx,
             inputs
           ) do
        {true, encoded_state} -> {:ok, encoded_state}
        _ -> {:error, :invalid_contract_execution}
      end
    else
      {:error, :invalid_contract_context_inputs}
    end
  end

  defp validate_consensus(
         tx = %Transaction{
           cross_validation_stamps: cross_stamps
         }
       ) do
    with :ok <- validate_atomic_commitment(tx) do
      validate_cross_validation_stamps_inconsistencies(cross_stamps)
    end
  end

  defp validate_atomic_commitment(tx) do
    if Transaction.atomic_commitment?(tx) do
      :ok
    else
      {:error, :invalid_atomic_commitment}
    end
  end

  defp validate_cross_validation_stamps_inconsistencies(stamps) do
    if Enum.all?(stamps, &(&1.inconsistencies == [])) do
      :ok
    else
      Logger.error("Inconsistencies: #{inspect(Enum.map(stamps, & &1.inconsistencies))}")
      {:error, :invalid_transaction_with_inconsistencies}
    end
  end

  defp validate_validation_stamp(tx = %Transaction{}) do
    with :ok <- validate_proof_of_work(tx),
         :ok <- validate_node_election(tx),
         :ok <- validate_transaction_movements(tx) do
      validate_no_additional_error(tx)
    end
  end

  defp validate_proof_of_work(
         tx = %Transaction{validation_stamp: %ValidationStamp{proof_of_work: pow}}
       ) do
    if Transaction.verify_origin_signature?(tx, pow) do
      :ok
    else
      Logger.error("Invalid proof of work #{Base.encode16(pow)}",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      {:error, :invalid_proof_of_work}
    end
  end

  defp validate_node_election(tx = %Transaction{}) do
    if valid_election?(tx) do
      :ok
    else
      {:error, :invalid_node_election}
    end
  end

  defp valid_election?(
         tx = %Transaction{
           address: tx_address,
           validation_stamp: %ValidationStamp{
             timestamp: tx_timestamp,
             proof_of_election: proof_of_election
           }
         }
       ) do
    authorized_nodes = P2P.authorized_and_available_nodes(tx_timestamp)

    daily_nonce_public_key = SharedSecrets.get_daily_nonce_public_key(tx_timestamp)

    case authorized_nodes do
      [] ->
        # Should happens only during the network bootstrapping
        daily_nonce_public_key == SharedSecrets.genesis_daily_nonce_public_key()

      _ ->
        storage_nodes = Election.chain_storage_nodes(tx_address, authorized_nodes)

        validation_nodes_public_key =
          Election.validation_nodes(
            tx,
            proof_of_election,
            authorized_nodes,
            storage_nodes,
            Election.get_validation_constraints()
          )
          # Update node last public key with the one at transaction date
          |> Enum.map(fn %Node{first_public_key: public_key} ->
            [DB.get_last_chain_public_key(public_key, tx_timestamp)]
          end)

        Transaction.valid_stamps_signature?(tx, validation_nodes_public_key)
    end
  end

  defp validate_transaction_fee(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: fee}}
         },
         contract_recipient_fees,
         contract_context,
         encoded_state
       ) do
    if fee == get_transaction_fee(tx, contract_recipient_fees, contract_context, encoded_state) do
      :ok
    else
      Logger.error(
        "Invalid fee: #{inspect(fee)}",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      {:error, :invalid_transaction_fee}
    end
  end

  defp get_transaction_fee(
         tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}},
         contract_recipient_fees,
         contract_context,
         encoded_state
       ) do
    previous_usd_price =
      timestamp
      |> OracleChain.get_last_scheduling_date()
      |> OracleChain.get_uco_price()
      |> Keyword.fetch!(:usd)

    Mining.get_transaction_fee(
      tx,
      contract_context,
      previous_usd_price,
      timestamp,
      encoded_state,
      contract_recipient_fees
    )
  end

  defp validate_transaction_movements(
         tx = %Transaction{
           type: tx_type,
           validation_stamp: %ValidationStamp{
             ledger_operations:
               ops = %LedgerOperations{transaction_movements: transaction_movements}
           }
         }
       ) do
    resolved_addresses = TransactionChain.resolve_transaction_addresses!(tx)
    movements = Transaction.get_movements(tx)

    %LedgerOperations{transaction_movements: resolved_movements} =
      %LedgerOperations{}
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx_type)

    with true <- length(resolved_movements) == length(transaction_movements),
         true <- Enum.all?(resolved_movements, &(&1 in transaction_movements)) do
      :ok
    else
      false ->
        Logger.error(
          "Invalid movements: #{inspect(ops.transaction_movements)}",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        {:error, :invalid_transaction_movements}
    end
  end

  defp validate_no_additional_error(%Transaction{validation_stamp: %ValidationStamp{error: nil}}),
    do: :ok

  defp validate_no_additional_error(
         tx = %Transaction{validation_stamp: %ValidationStamp{error: error}}
       ) do
    Logger.info(
      "Contains errors: #{inspect(error)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    {:error, error}
  end

  defp validate_inputs(
         tx = %Transaction{address: address},
         inputs,
         encoded_state,
         contract_context
       ) do
    if address == Bootstrap.genesis_address() do
      :ok
    else
      do_validate_inputs(tx, inputs, encoded_state, contract_context)
    end
  end

  defp do_validate_inputs(
         tx = %Transaction{
           address: address,
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{fee: fee},
             timestamp: timestamp,
             protocol_version: protocol_version
           }
         },
         inputs,
         encoded_state,
         contract_context
       ) do
    {sufficient_funds?, ledger_operations} =
      LedgerOperations.consume_inputs(
        %LedgerOperations{fee: fee},
        address,
        timestamp,
        inputs,
        Transaction.get_movements(tx),
        LedgerOperations.get_utxos_from_transaction(tx, timestamp, protocol_version),
        encoded_state,
        contract_context
      )

    with :ok <- validate_sufficient_funds(sufficient_funds?),
         :ok <- validate_consume_inputs(tx, ledger_operations) do
      validate_unspent_outputs(tx, ledger_operations)
    end
  end

  defp validate_sufficient_funds(true), do: :ok
  defp validate_sufficient_funds(false), do: {:error, :insufficient_funds}

  defp validate_consume_inputs(
         %Transaction{
           address: address,
           type: type,
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{consumed_inputs: consumed_inputs}
           }
         },
         %LedgerOperations{consumed_inputs: expected_consumed_inputs}
       ) do
    if length(consumed_inputs) == length(expected_consumed_inputs) and
         Enum.all?(consumed_inputs, &(&1 in expected_consumed_inputs)) do
      :ok
    else
      Logger.error(
        "Invalid consumed inputs - got: #{inspect(consumed_inputs)}, expected: #{inspect(expected_consumed_inputs)}",
        transaction_address: Base.encode16(address),
        transaction_type: type
      )

      {:error, :invalid_consumed_inputs}
    end
  end

  defp validate_unspent_outputs(
         %Transaction{
           address: address,
           type: type,
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{unspent_outputs: next_unspent_outputs}
           }
         },
         %LedgerOperations{unspent_outputs: expected_unspent_outputs}
       ) do
    if length(next_unspent_outputs) == length(expected_unspent_outputs) and
         Enum.all?(next_unspent_outputs, &(&1 in expected_unspent_outputs)) do
      :ok
    else
      Logger.error(
        "Invalid unspent outputs - got: #{inspect(next_unspent_outputs)}, expected: #{inspect(expected_unspent_outputs)}",
        transaction_address: Base.encode16(address),
        transaction_type: type
      )

      {:error, :invalid_unspent_outputs}
    end
  end
end
