defmodule Archethic.Replication.TransactionValidator do
  @moduledoc false

  alias Archethic.Bootstrap

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract

  alias Archethic.DB

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Mining

  alias Archethic.OracleChain

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.TransactionInput

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
          | :invalid_contract_acceptance
          | :invalid_pending_transaction
          | :invalid_inherit_constraints
          | :invalid_validation_stamp_signature
          | :invalid_unspent_outputs

  @doc """
  Validate transaction only (without chain integrity or unspent outputs)

  This function called by the replication nodes which are involved in the I/O storage
  """
  @spec validate(tx :: Transaction.t()) :: :ok | {:error, error()}
  def validate(tx = %Transaction{}) do
    with :ok <- validate_consensus(tx),
         :ok <- validate_validation_stamp(tx) do
      :ok
    end
  end

  @doc """
  Validate transaction with context

  This function is called by the chain replication nodes
  """
  @spec validate(
          validated_transaction :: Transaction.t(),
          prev_tx :: Transaction.t() | nil,
          inputs_outputs :: list(TransactionInput.t()),
          contract_context :: nil | Contract.Context.t()
        ) ::
          :ok | {:error, error()}
  def validate(tx = %Transaction{}, prev_tx, inputs, contract_context) do
    with :ok <- validate(tx),
         :ok <- validate_inputs(tx, inputs, prev_tx, contract_context),
         :ok <- validate_inheritance(prev_tx, tx) do
      validate_chain(tx, prev_tx)
    end
  end

  # it is fine to assume validation_stamp is valid because this step is done after validate_validation_stamp
  defp validate_inheritance(
         prev_tx = %Transaction{data: %TransactionData{code: code}},
         next_tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: validation_time}}
       )
       when code != "" do
    if Contracts.valid_condition?(
         :inherit,
         Contract.from_transaction!(prev_tx),
         next_tx,
         nil,
         validation_time
       ) do
      :ok
    else
      {:error, :invalid_contract_acceptance}
    end
  end

  # handle case:
  # - no prev tx
  # - prev tx has no inherit condition
  defp validate_inheritance(_prev_tx, _next_tx), do: :ok

  defp validate_chain(tx, prev_tx) do
    if TransactionChain.valid?([tx, prev_tx]) do
      :ok
    else
      {:error, :invalid_chain}
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
         :ok <- validate_transaction_fee(tx),
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
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{fee: fee}
           }
         }
       ) do
    if fee == get_transaction_fee(tx) do
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
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             timestamp: timestamp
           }
         }
       ) do
    previous_usd_price =
      timestamp
      |> OracleChain.get_last_scheduling_date()
      |> OracleChain.get_uco_price()
      |> Keyword.fetch!(:usd)

    Mining.get_transaction_fee(tx, previous_usd_price, timestamp)
  end

  defp validate_transaction_movements(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             timestamp: timestamp,
             ledger_operations:
               ops = %LedgerOperations{transaction_movements: transaction_movements}
           }
         }
       ) do
    resolved_addresses = TransactionChain.resolve_transaction_addresses(tx, timestamp)

    initial_movements =
      tx
      |> Transaction.get_movements()
      |> Enum.map(&{{&1.to, &1.type}, &1})
      |> Enum.into(%{})

    resolved_movements =
      Enum.reduce(resolved_addresses, [], fn {to, resolved}, acc ->
        case Map.get(initial_movements, to) do
          nil ->
            acc

          movement ->
            [%{movement | to: resolved} | acc]
        end
      end)

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
         prev_tx,
         contract_context
       ) do
    if address == Bootstrap.genesis_address() do
      :ok
    else
      do_validate_inputs(tx, inputs, prev_tx, contract_context)
    end
  end

  defp do_validate_inputs(
         tx = %Transaction{
           type: type,
           address: address,
           validation_stamp: %ValidationStamp{
             timestamp: timestamp,
             ledger_operations: %LedgerOperations{
               unspent_outputs: next_unspent_outputs,
               fee: fee,
               transaction_movements: transaction_movements
             }
           }
         },
         inputs,
         prev_tx,
         contract_context
       ) do
    # maybe execute the contract to get the state
    maybe_state_utxo =
      case Archethic.Mining.SmartContractValidation.valid_contract_execution?(
             contract_context,
             prev_tx,
             tx
           ) do
        {true, %Contract.Result.Success{state_utxo: state_utxo}} ->
          state_utxo

        _ ->
          nil
      end

    case LedgerOperations.consume_inputs(
           %LedgerOperations{
             fee: fee,
             transaction_movements: transaction_movements,
             tokens_to_mint: LedgerOperations.get_utxos_from_transaction(tx, timestamp)
           },
           address,
           inputs,
           timestamp,
           maybe_state_utxo
         ) do
      {false, _} ->
        {:error, :insufficient_funds}

      {true, %LedgerOperations{unspent_outputs: expected_unspent_outputs}} ->
        same? =
          Enum.all?(next_unspent_outputs, fn %{amount: amount, from: from} ->
            Enum.any?(expected_unspent_outputs, &(&1.from == from and &1.amount >= amount))
          end)

        if same? do
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
end
