defmodule Uniris.Replication.TransactionValidator do
  @moduledoc false

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.Mining

  alias Uniris.Replication

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.TransactionChain.TransactionInput

  @doc """
  Validate transaction with context
  """
  @spec validate(Transaction.t(), Transaction.t(), list(UnspentOutput.t() | TransactionInput.t())) ::
          :ok | {:error, :invalid}
  def validate(tx = %Transaction{}, previous_transaction, inputs_outputs) do
    with true <- valid_transaction?(tx, inputs_outputs),
         true <- TransactionChain.valid?([tx, previous_transaction]) do
      :ok
    else
      false ->
        {:error, :invalid}
    end
  end

  @doc """
  Validate transaction only
  """
  @spec validate(Transaction.t()) :: :ok | {:error, :invalid}
  def validate(tx = %Transaction{}) do
    if valid_transaction?(tx) do
      :ok
    else
      {:error, :invalid}
    end
  end

  defp valid_transaction?(tx = %Transaction{}) do
    with true <- do_validate_transaction(tx),
         true <- correct_validation_stamp?(tx) do
      true
    end
  end

  defp valid_transaction?(tx = %Transaction{}, previous_inputs_unspent_outputs \\ []) do
    with true <- do_validate_transaction(tx),
         true <- correct_validation_stamp?(tx, previous_inputs_unspent_outputs) do
      true
    end
  end

  defp do_validate_transaction(
         tx = %Transaction{
           validation_stamp: validation_stamp,
           cross_validation_stamps: cross_stamps
         }
       ) do
    with true <- Mining.accept_transaction?(tx),
         true <- atomic_commitment?(tx),
         true <-
           Enum.all?(cross_stamps, &CrossValidationStamp.valid_signature?(&1, validation_stamp)),
         true <- Enum.all?(cross_stamps, &(&1.inconsistencies == [])),
         true <- valid_node_election?(tx) do
      true
    else
      _ ->
        false
    end
  end

  defp atomic_commitment?(tx) do
    # TODO: start malicious detection if not
    Transaction.atomic_commitment?(tx)
  end

  defp correct_validation_stamp?(
         tx = %Transaction{
           validation_stamp:
             validation_stamp = %ValidationStamp{
               proof_of_work: pow,
               ledger_operations:
                 ops = %LedgerOperations{
                   fee: fee,
                   transaction_movements: transaction_movements,
                   node_movements: node_movements
                 }
             },
           cross_validation_stamps: cross_stamps
         }
       ) do
    coordinator_node_public_key =
      get_coordinator_node_public_key_from_node_movements(node_movements)

    cross_validation_node_public_keys = Enum.map(cross_stamps, & &1.node_public_key)

    with true <- Transaction.verify_origin_signature?(tx, pow),
         true <- ValidationStamp.valid_signature?(validation_stamp, coordinator_node_public_key),
         true <- fee == Transaction.fee(tx),
         true <- transaction_movements == Transaction.get_movements(tx),
         true <- LedgerOperations.valid_node_movements_roles?(ops),
         true <-
           LedgerOperations.valid_node_movements_cross_validation_nodes?(
             ops,
             cross_validation_node_public_keys
           ),
         true <- LedgerOperations.valid_reward_distribution?(ops) do
      true
    end
  end

  defp correct_validation_stamp?(
         tx = %Transaction{
           validation_stamp:
             validation_stamp = %ValidationStamp{
               proof_of_work: pow,
               ledger_operations:
                 ops = %LedgerOperations{
                   fee: fee,
                   transaction_movements: transaction_movements,
                   unspent_outputs: next_unspent_outputs,
                   node_movements: node_movements
                 }
             },
           cross_validation_stamps: cross_stamps
         },
         previous_inputs_unspent_outputs
       ) do
    previous_storage_nodes_public_keys =
      previous_storage_node_public_keys(tx, previous_inputs_unspent_outputs)

    coordinator_node_public_key =
      get_coordinator_node_public_key_from_node_movements(node_movements)

    cross_validation_node_public_keys = Enum.map(cross_stamps, & &1.node_public_key)

    with true <- Transaction.verify_origin_signature?(tx, pow),
         true <-
           ValidationStamp.valid_signature?(validation_stamp, coordinator_node_public_key),
         %LedgerOperations{
           fee: expected_fee,
           transaction_movements: expected_transaction_movements,
           unspent_outputs: expected_unspent_outputs
         } <- new_ledger_operations(tx, previous_inputs_unspent_outputs),
         true <- fee == expected_fee,
         true <- transaction_movements == expected_transaction_movements,
         true <- LedgerOperations.valid_node_movements_roles?(ops),
         true <-
           LedgerOperations.valid_node_movements_cross_validation_nodes?(
             ops,
             cross_validation_node_public_keys
           ),
         true <-
           LedgerOperations.valid_node_movements_previous_storage_nodes?(
             ops,
             previous_storage_nodes_public_keys
           ),
         true <- LedgerOperations.valid_reward_distribution?(ops) do
      case previous_inputs_unspent_outputs do
        [] ->
          LedgerOperations.sufficient_funds?(ops, previous_inputs_unspent_outputs)

        _ ->
          with true <- compare_unspent_outputs(next_unspent_outputs, expected_unspent_outputs),
               true <- LedgerOperations.sufficient_funds?(ops, previous_inputs_unspent_outputs) do
            true
          end
      end
    end
  end

  defp compare_unspent_outputs(next, expected) do
    Enum.all?(next, fn %{amount: amount, from: from} ->
      Enum.any?(expected, &(&1.from == from and &1.amount == amount))
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
    tx
    |> Transaction.to_pending()
    |> LedgerOperations.from_transaction()
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
    case P2P.get_node_info() do
      %Node{authorized?: true} ->
        coordinator_node_public_key =
          get_coordinator_node_public_key_from_node_movements(node_movements)

        validation_nodes =
          Enum.uniq([
            coordinator_node_public_key | Enum.map(cross_validation_stamps, & &1.node_public_key)
          ])

        Mining.valid_election?(Transaction.to_pending(tx), validation_nodes)

      %Node{} ->
        true
    end
  end

  defp get_coordinator_node_public_key_from_node_movements(node_movements) do
    %NodeMovement{to: coordinator_node_public_key} =
      Enum.find(node_movements, &(:coordinator_node in &1.roles))

    coordinator_node_public_key
  end
end
