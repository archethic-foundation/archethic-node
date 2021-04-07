defmodule Uniris.Replication.TransactionValidator do
  @moduledoc false

  alias Uniris.Bootstrap
  alias Uniris.Contracts

  alias Uniris.Election

  alias Uniris.P2P

  alias Uniris.Mining

  alias Uniris.Replication

  alias Uniris.SharedSecrets

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionInput

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
  """
  @spec validate(
          validated_transaction :: Transaction.t(),
          previous_transaction :: Transaction.t(),
          inputs_outputs :: list(UnspentOutput.t()) | list(TransactionInput.t()),
          self_repair? :: boolean()
        ) ::
          :ok | {:error, error()}
  def validate(tx = %Transaction{}, previous_transaction, inputs_outputs, self_repair? \\ false) do
    with :ok <- valid_transaction(tx, inputs_outputs, self_repair?),
         true <- Contracts.accept_new_contract?(previous_transaction, tx),
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
  Validate transaction only
  """
  @spec validate(validated_tx :: Transaction.t(), self_repair? :: boolean()) ::
          :ok | {:error, error()}
  def validate(tx = %Transaction{}, self_repair? \\ false),
    do: valid_transaction(tx, [], self_repair?)

  defp valid_transaction(tx = %Transaction{}, [], self_repair?) do
    with :ok <- do_validate_transaction(tx, self_repair?),
         :ok <- validate_without_unspent_outputs(tx) do
      :ok
    end
  end

  defp valid_transaction(tx = %Transaction{}, previous_inputs_unspent_outputs, self_repair?) do
    with :ok <- do_validate_transaction(tx, self_repair?),
         :ok <- validate_without_unspent_outputs(tx),
         :ok <- validate_with_unspent_outputs(tx, previous_inputs_unspent_outputs) do
      :ok
    end
  end

  defp do_validate_transaction(
         tx = %Transaction{
           validation_stamp: validation_stamp = %ValidationStamp{errors: errors},
           cross_validation_stamps: cross_stamps
         },
         self_repair?
       ) do
    with {:atomic_commitment, true} <-
           {:atomic_commitment, Transaction.atomic_commitment?(tx)},
         {:cross_stamps_signatures, true} <-
           {:cross_stamps_signatures,
            Enum.all?(cross_stamps, &CrossValidationStamp.valid_signature?(&1, validation_stamp))},
         {:no_inconsistencies, true} <-
           {:no_inconsistencies, Enum.all?(cross_stamps, &(&1.inconsistencies == []))},
         {:election, true} <- {:election, valid_node_election?(tx, self_repair?)},
         {:errors, true} <- {:errors, errors == []} do
      :ok
    else
      {:atomic_commitment, false} ->
        # TODO: start malicious detection
        {:error, :invalid_atomic_commitment}

      {:cross_stamps_signatures, false} ->
        {:error, :invalid_cross_validation_stamp_signatures}

      {:no_inconsistencies, false} ->
        Logger.debug("Inconsistencies: #{inspect(Enum.map(cross_stamps, & &1.inconsistencies))}")
        {:error, :invalid_transaction_with_inconsistencies}

      {:election, false} ->
        {:error, :invalid_node_election}

      {:errors, false} ->
        {:error, {:transaction_errors_detected, errors}}
    end
  end

  defp validate_without_unspent_outputs(
         tx = %Transaction{
           timestamp: timestamp,
           validation_stamp:
             validation_stamp = %ValidationStamp{
               proof_of_work: pow,
               proof_of_election: poe,
               ledger_operations:
                 ops = %LedgerOperations{
                   fee: fee,
                   node_movements: node_movements,
                   transaction_movements: transaction_movements
                 },
               errors: errors
             },
           cross_validation_stamps: cross_stamps
         }
       ) do
    coordinator_node_public_key =
      get_coordinator_node_public_key_from_node_movements(node_movements)

    cross_validation_node_public_keys = Enum.map(cross_stamps, & &1.node_public_key)

    resolved_tx_movements = resolve_transaction_movements(tx)

    with {:pow, true} <- {:pow, Transaction.verify_origin_signature?(tx, pow)},
         {:poe, true} <-
           {:poe,
            Election.valid_proof_of_election?(
              tx,
              poe,
              SharedSecrets.get_daily_nonce_public_key_at(timestamp)
            )},
         {:signature, true} <-
           {:signature,
            ValidationStamp.valid_signature?(validation_stamp, coordinator_node_public_key)},
         {:fee, true} <- {:fee, fee == Transaction.fee(tx)},
         {:tx_movements, true} <- {:tx_movements, resolved_tx_movements == transaction_movements},
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
        {:error, :invalid_proof_of_work}

      {:poe, false} ->
        {:error, :invalid_proof_of_election}

      {:signature, false} ->
        {:error, :invalid_validation_stamp_signature}

      {:fee, false} ->
        {:error, :invalid_transaction_fee}

      {:tx_movements, false} ->
        {:error, :invalid_transaction_movements}

      {:node_movements_roles, false} ->
        {:error, :invalid_node_movements_roles}

      {:node_movements_election, false} ->
        {:error, :invalid_cross_validation_nodes_movements}

      {:node_movements_rewards, false} ->
        {:error, :invalid_reward_distribution}

      {:errors, false} ->
        {:error, {:transaction_errors_detected, errors}}
    end
  end

  defp validate_with_unspent_outputs(
         tx = %Transaction{
           address: address,
           validation_stamp: %ValidationStamp{ledger_operations: ops}
         },
         previous_inputs_unspent_outputs
       ) do
    previous_storage_nodes_public_keys =
      previous_storage_node_public_keys(tx, previous_inputs_unspent_outputs)

    if LedgerOperations.valid_node_movements_previous_storage_nodes?(
         ops,
         previous_storage_nodes_public_keys
       ) do
      %LedgerOperations{unspent_outputs: expected_unspent_outputs} =
        new_ledger_operations(tx, previous_inputs_unspent_outputs)

      if address == Bootstrap.genesis_address() do
        true
      else
        validate_unspent_outputs(previous_inputs_unspent_outputs, ops, expected_unspent_outputs)
      end
    else
      {:error, :invalid_previous_storage_nodes_movements}
    end
  end

  defp validate_unspent_outputs([], ops, _) do
    if LedgerOperations.sufficient_funds?(ops, []) do
      :ok
    else
      {:error, :insufficient_funds}
    end
  end

  defp validate_unspent_outputs(
         previous_inputs_unspent_outputs,
         ops = %LedgerOperations{unspent_outputs: next_unspent_outputs},
         expected_unspent_outputs
       ) do
    cond do
      !compare_unspent_outputs(next_unspent_outputs, expected_unspent_outputs) ->
        {:error, :invalid_unspent_outputs}

      !LedgerOperations.sufficient_funds?(ops, previous_inputs_unspent_outputs) ->
        {:error, :insufficient_funds}

      true ->
        :ok
    end
  end

  defp compare_unspent_outputs(next, expected) do
    Enum.all?(next, fn %{amount: amount, from: from} ->
      Enum.any?(expected, &(&1.from == from and &1.amount >= amount))
    end)
  end

  defp previous_storage_node_public_keys(
         tx = %Transaction{type: type},
         previous_inputs_unspent_outputs
       ) do
    node_list = P2P.list_nodes(availability: :global)

    inputs_unspent_outputs_storage_nodes =
      previous_inputs_unspent_outputs
      |> Stream.map(& &1.from)
      |> Stream.flat_map(&Replication.chain_storage_nodes(&1, node_list))
      |> Enum.to_list()

    P2P.distinct_nodes([
      Replication.chain_storage_nodes(Transaction.previous_address(tx), type, node_list),
      inputs_unspent_outputs_storage_nodes
    ])
    |> Enum.map(& &1.last_public_key)
  end

  defp new_ledger_operations(tx, previous_unspent_outputs) do
    %LedgerOperations{
      fee: Transaction.fee(tx),
      transaction_movements: resolve_transaction_movements(tx)
    }
    |> LedgerOperations.from_transaction(tx)
    |> LedgerOperations.consume_inputs(tx.address, previous_unspent_outputs)
  end

  defp resolve_transaction_movements(tx) do
    tx
    |> Transaction.get_movements()
    |> Task.async_stream(fn mvt = %TransactionMovement{to: to} ->
      %{mvt | to: TransactionChain.resolve_last_address(to, tx.timestamp)}
    end)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Enum.into([], fn {:ok, res} -> res end)
  end

  # defp valid_node_election?(_tx, true), do: true

  defp valid_node_election?(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{
               node_movements: node_movements
             }
           },
           cross_validation_stamps: cross_validation_stamps
         },
         _self_repair?
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
