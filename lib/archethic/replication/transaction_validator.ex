defmodule Archethic.Replication.TransactionValidator do
  @moduledoc false

  alias Archethic.Bootstrap

  alias Archethic.Contracts

  alias Archethic.DB

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Mining

  alias Archethic.OracleChain

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
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
  Validate transaction with context

  This function is called by the chain replication nodes
  """
  @spec validate(
          validated_transaction :: Transaction.t(),
          previous_transaction :: Transaction.t() | nil,
          inputs_outputs :: list(TransactionInput.t())
        ) ::
          :ok | {:error, error()}
  def validate(tx = %Transaction{}, previous_transaction, inputs) do
    with :ok <- valid_transaction(tx, inputs, true),
         :ok <- validate_inheritance(tx, previous_transaction) do
      validate_chain(tx, previous_transaction)
    end
  end

  defp validate_inheritance(
         tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}},
         prev_tx
       ) do
    if Contracts.accept_new_contract?(prev_tx, tx, timestamp) do
      :ok
    else
      {:error, :invalid_contract_acceptance}
    end
  end

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
  def validate(tx = %Transaction{}),
    do: valid_transaction(tx, [], false)

  defp valid_transaction(tx = %Transaction{}, inputs, chain_node?) when is_list(inputs) do
    with :ok <- validate_consensus(tx),
         :ok <- validate_validation_stamp(tx) do
      if chain_node? do
        check_inputs(tx, inputs)
      else
        :ok
      end
    else
      {:error, _} = e ->
        # TODO: start malicious detection
        e
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
           validation_stamp:
             validation_stamp = %ValidationStamp{
               timestamp: tx_timestamp,
               proof_of_election: proof_of_election
             },
           cross_validation_stamps: cross_validation_stamps
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

        validation_nodes =
          Election.validation_nodes(
            tx,
            proof_of_election,
            authorized_nodes,
            storage_nodes,
            Election.get_validation_constraints()
          )
          # Update node last public key with the one at transaction date
          |> Enum.map(fn node = %Node{first_public_key: public_key} ->
            last_public_key = DB.get_last_chain_public_key(public_key, tx_timestamp)
            %{node | last_public_key: last_public_key}
          end)

        valid_coordinator? =
          Enum.any?(
            validation_nodes,
            &ValidationStamp.valid_signature?(validation_stamp, &1.last_public_key)
          )

        valid_cross_validators? =
          Enum.all?(
            cross_validation_stamps,
            fn cross_stamp = %CrossValidationStamp{node_public_key: node_public_key} ->
              Enum.any?(validation_nodes, &(&1.last_public_key == node_public_key)) and
                CrossValidationStamp.valid_signature?(cross_stamp, validation_stamp)
            end
          )

        valid_coordinator? and valid_cross_validators?
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

  defp check_inputs(
         tx = %Transaction{address: address},
         inputs
       ) do
    if address == Bootstrap.genesis_address() do
      :ok
    else
      do_check_inputs(tx, inputs)
    end
  end

  defp do_check_inputs(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: ops = %LedgerOperations{}
           }
         },
         inputs
       ) do
    with :ok <- validate_inputs(tx, inputs) do
      validate_funds(ops, inputs)
    end
  end

  defp validate_inputs(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{
               unspent_outputs: next_unspent_outputs,
               fee: fee,
               transaction_movements: transaction_movements
             }
           }
         },
         inputs
       ) do
    %LedgerOperations{unspent_outputs: expected_unspent_outputs} =
      %LedgerOperations{
        fee: fee,
        transaction_movements: transaction_movements
      }
      |> LedgerOperations.from_transaction(tx, tx.validation_stamp.timestamp)
      |> LedgerOperations.consume_inputs(tx.address, inputs, tx.validation_stamp.timestamp)

    same? =
      Enum.all?(next_unspent_outputs, fn %{amount: amount, from: from} ->
        Enum.any?(expected_unspent_outputs, &(&1.from == from and &1.amount >= amount))
      end)

    if same? do
      :ok
    else
      Logger.error(
        "Invalid unspent outputs - got: #{inspect(next_unspent_outputs)}, expected: #{inspect(expected_unspent_outputs)}",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      {:error, :invalid_unspent_outputs}
    end
  end

  defp validate_funds(ops = %LedgerOperations{}, inputs) do
    if LedgerOperations.sufficient_funds?(ops, inputs) do
      :ok
    else
      {:error, :insufficient_funds}
    end
  end
end
