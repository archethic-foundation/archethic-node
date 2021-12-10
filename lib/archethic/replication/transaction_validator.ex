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
        tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}},
        previous_transaction,
        inputs_outputs
      ) do
    with :ok <- valid_transaction(tx, inputs_outputs, true),
         true <- Contracts.accept_new_contract?(previous_transaction, tx, timestamp),
         true <- TransactionChain.valid?([tx, previous_transaction]) do
      :ok
    else
      {:error, reason} ->
        {:error, reason}

      false ->
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
    with :ok <- check_consensus(tx),
         :ok <- check_validation_stamp(tx),
         {:election, true} <- {:election, valid_node_election?(tx)} do
      if chain_node? do
        check_unspent_outputs(tx, previous_inputs_unspent_outputs)
      else
        :ok
      end
    else
      {:election, false} ->
        {:error, :invalid_node_election}

      {:error, _} = e ->
        # TODO: start malicious detection
        e
    end
  end

  defp check_consensus(
         tx = %Transaction{
           validation_stamp: validation_stamp = %ValidationStamp{},
           cross_validation_stamps: cross_stamps
         }
       ) do
    with {:atomic_commitment, true} <-
           {:atomic_commitment, Transaction.atomic_commitment?(tx)},
         {:cross_stamps_signatures, true} <-
           {:cross_stamps_signatures,
            Enum.all?(cross_stamps, &CrossValidationStamp.valid_signature?(&1, validation_stamp))},
         {:no_inconsistencies, true} <-
           {:no_inconsistencies, Enum.all?(cross_stamps, &(&1.inconsistencies == []))} do
      :ok
    else
      {:atomic_commitment, false} ->
        {:error, :invalid_atomic_commitment}

      {:cross_stamps_signatures, false} ->
        {:error, :invalid_cross_validation_stamp_signatures}

      {:no_inconsistencies, false} ->
        Logger.debug("Inconsistencies: #{inspect(Enum.map(cross_stamps, & &1.inconsistencies))}")
        {:error, :invalid_transaction_with_inconsistencies}
    end
  end

  defp check_validation_stamp(
         tx = %Transaction{
           validation_stamp:
             validation_stamp = %ValidationStamp{
               timestamp: timestamp,
               proof_of_work: pow,
               proof_of_election: poe,
               ledger_operations:
                 ops = %LedgerOperations{
                   fee: fee,
                   node_movements: node_movements
                 },
               errors: errors
             },
           cross_validation_stamps: cross_stamps
         }
       ) do
    coordinator_node_public_key =
      get_coordinator_node_public_key_from_node_movements(node_movements)

    cross_validation_node_public_keys = Enum.map(cross_stamps, & &1.node_public_key)

    with {:pow, true} <- {:pow, Transaction.verify_origin_signature?(tx, pow)},
         {:poe, true} <-
           {:poe,
            Election.valid_proof_of_election?(
              tx,
              poe,
              SharedSecrets.get_daily_nonce_public_key(timestamp)
            )},
         {:signature, true} <-
           {:signature,
            ValidationStamp.valid_signature?(validation_stamp, coordinator_node_public_key)},
         {:fee, true} <- {:fee, fee == get_transaction_fee(tx)},
         {:tx_movements, true} <-
           {:tx_movements,
            LedgerOperations.valid_transaction_movements?(
              ops,
              Transaction.get_movements(tx),
              timestamp
            )},
         {:node_movements_roles, true} <-
           {:node_movements_roles, LedgerOperations.valid_node_movements_roles?(ops)},
         {:node_movements_election, true} <-
           {:node_movements_election,
            LedgerOperations.valid_node_movements_cross_validation_nodes?(
              ops,
              cross_validation_node_public_keys
            )},
         {:node_movements_rewards, true} <-
           {:node_movements_rewards, LedgerOperations.valid_reward_distribution?(ops)},
         {:errors, true} <- {:errors, errors == []} do
      :ok
    else
      {:pow, false} ->
        Logger.debug("Invalid proof of work #{Base.encode16(pow)}",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        {:error, :invalid_proof_of_work}

      {:poe, false} ->
        Logger.debug(
          "Invalid proof of election - checking public key: #{Base.encode16(SharedSecrets.get_daily_nonce_public_key(timestamp))}",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        {:error, :invalid_proof_of_election}

      {:signature, false} ->
        {:error, :invalid_validation_stamp_signature}

      {:fee, false} ->
        Logger.debug(
          "Invalid fee: #{inspect(fee)}",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        {:error, :invalid_transaction_fee}

      {:tx_movements, false} ->
        Logger.debug(
          "Invalid movements: #{inspect(ops.transaction_movements)}",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        {:error, :invalid_transaction_movements}

      {:node_movements_roles, false} ->
        {:error, :invalid_node_movements_roles}

      {:node_movements_election, false} ->
        {:error, :invalid_cross_validation_nodes_movements}

      {:node_movements_rewards, false} ->
        {:error, :invalid_reward_distribution}

      {:errors, false} ->
        Logger.debug(
          "Contains errors: #{inspect(errors)}",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        {:error, {:transaction_errors_detected, errors}}
    end
  end

  defp get_transaction_fee(
         tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}}
       ) do
    uco_price_usd =
      timestamp
      |> OracleChain.get_uco_price()
      |> Keyword.fetch!(:usd)

    Mining.get_transaction_fee(tx, uco_price_usd)
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
             ledger_operations: ops = %LedgerOperations{unspent_outputs: next_unspent_outputs}
           }
         },
         previous_inputs_unspent_outputs
       ) do
    previous_storage_nodes_public_keys =
      previous_storage_node_public_keys(tx, previous_inputs_unspent_outputs)

    %LedgerOperations{unspent_outputs: expected_unspent_outputs} =
      new_ledger_operations(tx, previous_inputs_unspent_outputs)

    with {:node_movements, true} <-
           {:node_movements,
            LedgerOperations.valid_node_movements_previous_storage_nodes?(
              ops,
              previous_storage_nodes_public_keys
            )},
         {:utxo, true} <-
           {:utxo, compare_unspent_outputs(next_unspent_outputs, expected_unspent_outputs)},
         {:funds, true} <-
           {:funds, LedgerOperations.sufficient_funds?(ops, previous_inputs_unspent_outputs)} do
      :ok
    else
      {:node_movements, false} ->
        {:error, :invalid_previous_storage_nodes_movements}

      {:utxo, false} ->
        {:error, :invalid_unspent_outputs}

      {:funds, false} ->
        {:error, :insufficient_funds}
    end
  end

  defp compare_unspent_outputs(next, expected) do
    Enum.all?(next, fn %{amount: amount, from: from} ->
      Enum.any?(expected, &(&1.from == from and &1.amount >= amount))
    end)
  end

  defp previous_storage_node_public_keys(
         tx = %Transaction{type: type, validation_stamp: %ValidationStamp{timestamp: timestamp}},
         previous_inputs_unspent_outputs
       ) do
    node_list = P2P.authorized_nodes(timestamp)

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

  defp valid_node_election?(
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

    Mining.valid_election?(tx, validation_nodes)
  end

  defp get_coordinator_node_public_key_from_node_movements(node_movements) do
    %NodeMovement{to: coordinator_node_public_key} =
      Enum.find(node_movements, &(:coordinator_node in &1.roles))

    coordinator_node_public_key
  end
end
