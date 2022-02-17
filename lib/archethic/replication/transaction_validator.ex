defmodule ArchEthic.Replication.TransactionValidator do
  @moduledoc false

  alias ArchEthic.Bootstrap
  alias ArchEthic.Contracts

  alias ArchEthic.Election

  alias ArchEthic.P2P

  alias ArchEthic.Mining

  alias ArchEthic.OracleChain

  alias ArchEthic.Replication

  alias ArchEthic.SharedSecrets

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.CrossValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionInput

  require Logger

  @typedoc """
  Represents the different errors during the validation for the transaction replication
  """
  @type error ::
          :invalid_atomic_commitment
          | :invalid_cross_validation_stamp_signatures
          | :invalid_transaction_with_inconsistencies
          | :invalid_node_election
          | :invalid_proof_of_work
          | :invalid_proof_of_election
          | :invalid_validation_stamp_signature
          | :invalid_transaction_fee
          | :invalid_transaction_movements
          | :invalid_node_movements_roles
          | :invalid_cross_validation_nodes_movements
          | :invalid_reward_distribution
          | :invalid_previous_storage_nodes_movements
          | :insufficient_funds
          | :invalid_unspent_outputs
          | :invalid_chain
          | :invalid_contract_acceptance
          | {:transaction_errors_detected, list(ValidationStamp.error())}

  @doc """
  Validate transaction with context

  This function is called by the chain replication nodes
  """
  @spec validate(
          validated_transaction :: Transaction.t(),
          previous_transaction :: Transaction.t() | nil,
          inputs_outputs :: list(UnspentOutput.t()) | list(TransactionInput.t())
        ) ::
          :ok | {:error, error()}
  def validate(
        tx = %Transaction{},
        previous_transaction,
        inputs_outputs
      ) do
    with :ok <- valid_transaction(tx, inputs_outputs, true),
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
  def validate(tx = %Transaction{}), do: valid_transaction(tx, [], false)

  defp valid_transaction(tx = %Transaction{}, previous_inputs_unspent_outputs, chain_node?)
       when is_list(previous_inputs_unspent_outputs) do
    with :ok <- validate_consensus(tx),
         :ok <- validate_validation_stamp(tx),
         :ok <- validate_node_election(tx) do
      if chain_node? do
        check_unspent_outputs(tx, previous_inputs_unspent_outputs)
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
           validation_stamp: validation_stamp = %ValidationStamp{},
           cross_validation_stamps: cross_stamps
         }
       ) do
    with :ok <- validate_atomic_commitment(tx),
         :ok <- validate_cross_validation_stamps_signatures(cross_stamps, validation_stamp) do
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

  defp validate_cross_validation_stamps_signatures(stamps, validation_stamp) do
    if Enum.all?(stamps, &CrossValidationStamp.valid_signature?(&1, validation_stamp)) do
      :ok
    else
      {:error, :invalid_cross_validation_stamp_signatures}
    end
  end

  defp validate_cross_validation_stamps_inconsistencies(stamps) do
    if Enum.all?(stamps, &(&1.inconsistencies == [])) do
      :ok
    else
      Logger.debug("Inconsistencies: #{inspect(Enum.map(stamps, & &1.inconsistencies))}")
      {:error, :invalid_transaction_with_inconsistencies}
    end
  end

  defp validate_validation_stamp(
         tx = %Transaction{validation_stamp: validation_stamp = %ValidationStamp{}}
       ) do
    with :ok <- validate_proof_of_work(tx),
         :ok <- validate_proof_of_election(tx),
         :ok <- validate_stamp_signature(validation_stamp),
         :ok <- validate_transaction_fee(tx),
         :ok <- validate_transaction_movements(tx),
         :ok <- validate_node_movements(tx) do
      validate_no_additional_errors(tx)
    end
  end

  defp validate_proof_of_work(
         tx = %Transaction{validation_stamp: %ValidationStamp{proof_of_work: pow}}
       ) do
    if Transaction.verify_origin_signature?(tx, pow) do
      :ok
    else
      Logger.debug("Invalid proof of work #{Base.encode16(pow)}",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      {:error, :invalid_proof_of_work}
    end
  end

  defp validate_proof_of_election(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{timestamp: timestamp, proof_of_election: poe}
         }
       ) do
    daily_nonce_public_key = SharedSecrets.get_daily_nonce_public_key(timestamp)

    if Election.valid_proof_of_election?(
         tx,
         poe,
         daily_nonce_public_key
       ) do
      :ok
    else
      Logger.debug(
        "Invalid proof of election - checking public key: #{Base.encode16(daily_nonce_public_key)}",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      {:error, :invalid_proof_of_election}
    end
  end

  defp validate_stamp_signature(
         validation_stamp = %ValidationStamp{
           ledger_operations: %LedgerOperations{node_movements: node_movements}
         }
       ) do
    coordinator_node_public_key =
      get_coordinator_node_public_key_from_node_movements(node_movements)

    if ValidationStamp.valid_signature?(validation_stamp, coordinator_node_public_key) do
      :ok
    else
      {:error, :invalid_validation_stamp_signature}
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
      Logger.debug(
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
    uco_price_usd =
      timestamp
      |> OracleChain.get_uco_price()
      |> Keyword.fetch!(:usd)

    Mining.get_transaction_fee(tx, uco_price_usd)
  end

  defp validate_transaction_movements(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{timestamp: timestamp, ledger_operations: ops}
         }
       ) do
    if LedgerOperations.valid_transaction_movements?(
         ops,
         Transaction.get_movements(tx),
         timestamp
       ) do
      :ok
    else
      Logger.debug(
        "Invalid movements: #{inspect(ops.transaction_movements)}",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      {:error, :invalid_transaction_movements}
    end
  end

  defp validate_node_movements(%Transaction{
         validation_stamp: %ValidationStamp{ledger_operations: ops},
         cross_validation_stamps: cross_stamps
       }) do
    with :ok <- validate_node_movements_roles(ops),
         :ok <- validate_node_movements_cross_validation_nodes(ops, cross_stamps) do
      validate_valid_reward_distribution(ops)
    end
  end

  defp validate_node_movements_roles(ops = %LedgerOperations{}) do
    if LedgerOperations.valid_node_movements_roles?(ops) do
      :ok
    else
      {:error, :invalid_node_movements_roles}
    end
  end

  defp validate_node_movements_cross_validation_nodes(
         ops = %LedgerOperations{},
         cross_validation_stamps
       ) do
    cross_validation_node_public_keys = Enum.map(cross_validation_stamps, & &1.node_public_key)

    if LedgerOperations.valid_node_movements_cross_validation_nodes?(
         ops,
         cross_validation_node_public_keys
       ) do
      :ok
    else
      {:error, :invalid_cross_validation_nodes_movements}
    end
  end

  defp validate_valid_reward_distribution(ops = %LedgerOperations{}) do
    if LedgerOperations.valid_reward_distribution?(ops) do
      :ok
    else
      {:error, :invalid_reward_distribution}
    end
  end

  defp validate_no_additional_errors(%Transaction{validation_stamp: %ValidationStamp{errors: []}}),
    do: :ok

  defp validate_no_additional_errors(
         tx = %Transaction{validation_stamp: %ValidationStamp{errors: errors}}
       ) do
    Logger.debug(
      "Contains errors: #{inspect(errors)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    {:error, {:transaction_errors_detected, errors}}
  end

  defp check_unspent_outputs(
         tx = %Transaction{type: type, address: address},
         previous_inputs_unspent_outputs
       ) do
    cond do
      address == Bootstrap.genesis_address() ->
        :ok

      Transaction.network_type?(type) ->
        :ok

      true ->
        do_check_unspent_outputs(tx, previous_inputs_unspent_outputs)
    end
  end

  defp do_check_unspent_outputs(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: ops = %LedgerOperations{}
           }
         },
         previous_inputs_unspent_outputs
       ) do
    previous_storage_nodes_public_keys =
      previous_storage_node_public_keys(tx, previous_inputs_unspent_outputs)

    with :ok <-
           validate_node_movements_previous_storage_nodes(ops, previous_storage_nodes_public_keys),
         :ok <- validate_unspent_outputs(tx, previous_inputs_unspent_outputs) do
      validate_funds(ops, previous_inputs_unspent_outputs)
    end
  end

  defp validate_node_movements_previous_storage_nodes(
         ops = %LedgerOperations{},
         previous_storage_nodes_public_keys
       ) do
    if LedgerOperations.valid_node_movements_previous_storage_nodes?(
         ops,
         previous_storage_nodes_public_keys
       ) do
      :ok
    else
      {:error, :invalid_previous_storage_nodes_movements}
    end
  end

  defp validate_unspent_outputs(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{unspent_outputs: next_unspent_outputs}
           }
         },
         previous_inputs_unspent_outputs
       ) do
    %LedgerOperations{unspent_outputs: expected_unspent_outputs} =
      new_ledger_operations(tx, previous_inputs_unspent_outputs)

    same? =
      Enum.all?(next_unspent_outputs, fn %{amount: amount, from: from} ->
        Enum.any?(expected_unspent_outputs, &(&1.from == from and &1.amount >= amount))
      end)

    if same? do
      :ok
    else
      Logger.debug(
        "Invalid unspent outputs - got: #{inspect(next_unspent_outputs)}, expected: #{inspect(expected_unspent_outputs)}",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      {:error, :invalid_unspent_outputs}
    end
  end

  defp validate_funds(ops = %LedgerOperations{}, previous_inputs_unspent_outputs) do
    if LedgerOperations.sufficient_funds?(ops, previous_inputs_unspent_outputs) do
      :ok
    else
      {:error, :insufficient_funds}
    end
  end

  defp previous_storage_node_public_keys(
         tx = %Transaction{type: type, validation_stamp: %ValidationStamp{timestamp: _timestamp}},
         previous_inputs_unspent_outputs
       ) do
    node_list = P2P.available_nodes()

    inputs_unspent_outputs_storage_nodes =
      previous_inputs_unspent_outputs
      |> Stream.map(& &1.from)
      |> Stream.flat_map(&Replication.chain_storage_nodes(&1, node_list))
      |> Enum.to_list()

    P2P.distinct_nodes([
      Replication.chain_storage_nodes_with_type(
        Transaction.previous_address(tx),
        type,
        node_list
      ),
      inputs_unspent_outputs_storage_nodes
    ])
    |> Enum.map(& &1.last_public_key)
  end

  defp new_ledger_operations(
         tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}},
         previous_unspent_outputs
       ) do
    %LedgerOperations{
      fee: get_transaction_fee(tx),
      transaction_movements:
        tx
        |> Transaction.get_movements()
        |> LedgerOperations.resolve_transaction_movements(timestamp)
    }
    |> LedgerOperations.from_transaction(tx)
    |> LedgerOperations.consume_inputs(tx.address, previous_unspent_outputs)
  end

  defp validate_node_election(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{
               node_movements: node_movements
             }
           },
           cross_validation_stamps: cross_validation_stamps
         }
       ) do
    coordinator_node_public_key =
      get_coordinator_node_public_key_from_node_movements(node_movements)

    validation_nodes =
      Enum.uniq([
        coordinator_node_public_key | Enum.map(cross_validation_stamps, & &1.node_public_key)
      ])

    if Mining.valid_election?(tx, validation_nodes) do
      :ok
    else
      {:error, :invalid_node_election}
    end
  end

  defp get_coordinator_node_public_key_from_node_movements(node_movements) do
    %NodeMovement{to: coordinator_node_public_key} =
      Enum.find(node_movements, &(:coordinator_node in &1.roles))

    coordinator_node_public_key
  end
end
