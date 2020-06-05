defmodule UnirisCore.Mining.Replication do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements
  alias UnirisCore.Transaction.ValidationStamp.NodeMovements
  alias UnirisCore.TaskSupervisor
  alias UnirisCore.Mining.Stamp
  alias UnirisCore.Mining.Fee
  alias UnirisCore.Mining.Context
  alias UnirisCore.Mining.ProofOfWork
  alias UnirisCore.Mining.ProofOfIntegrity
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.Election
  alias UnirisCore.Crypto

  require Logger

  @doc """
  Define a tree from a list of storage nodes and validation nodes by grouping
  closest closest nodes by the shorter path.

  # Examples

    Given a list of storage nodes: S1, S2, .., S16 and list of validation nodes: V1, .., V5

    Nodes coordinates (Network Patch ID : numerical value)

     S1: F36 -> 3894  S5: 143 -> 323   S9: 19A -> 410    S13: E2B -> 3627
     S2: A23 -> 2595  S6: BB2 -> 2994  S10: C2A -> 3114  S14: AA0 -> 2720
     S3: B43 -> 2883  S7: A63 -> 2659  S11: C23 -> 3107  S15: 042 -> 66
     S4: 2A9 -> 681   S8: D32 -> 3378  S12: F22 -> 3874  S16: 3BC -> 956

     V1: AC2 -> 2754  V2: DF3 -> 3571  V3: C22 -> 3106  V4: E19 -> 3609  V5: 22A -> 554

    The replication tree is computed by find the nearest storages nodes for each validations

    Foreach storage nodes its distance is computed with each validation nodes and then sorted to the get the closest.

    Table below shows the distance between storages and validations

      |------------|------------|------------|------------|------------|------------|-------------|------------|
      | S1         | S2         | S3         | S4         | S5         | S6         | S7          | S8         |
      |------------|------------|------------|------------|------------|------------|-------------|------------|
      |  V1 , 1140 |  V1 , 159  |  V1 , 129  |  V1 , 2073 |  V1 , 2431 |  V1 , 240  |  V1 , 95    |  V1 , 624  |
      |  V2 , 323  |  V2 , 976  |  V2 , 688  |  V2 , 2890 |  V2 , 3248 |  V2 , 577  |  V2 , 912   |  V2 , 193  |
      |  V3 , 788  |  V3 , 511  |  V3 , 223  |  V3 , 2425 |  V3 , 2783 |  V3 , 112  |  V3 , 447   |  V3 , 272  |
      |  V4 , 285  |  V4 , 1014 |  V4 , 726  |  V4 , 2928 |  V4 , 3286 |  V4 , 615  |  V4 , 950   |  V4 , 231  |
      |  V5 , 3340 |  V5 , 2041 |  V5 , 2329 |  V5 , 127  |  V5 , 231  |  V5 , 2440 |  V5 , 2105  |  V5 , 2824 |
      |------------|------------|------------|------------|------------|------------|-------------|------------|
      | S9         | S10        | S11        | S12        | S13        | S14        | S15         | S16        |
      |------------|------------|------------|------------|------------|------------|-------------|------------|
      |  V1 , 2344 |  V1 , 360  |  V1 , 353  |  V1 , 1120 |  V1 , 873  |  V1 , 34   |  V1 , 2688  |  V1 , 1798 |
      |  V2 , 3161 |  V2 , 457  |  V2 , 464  |  V2 , 303  |  V2 , 56   |  V2 , 851  |  V2 , 3505  |  V2 , 2615 |
      |  V3 , 2696 |  V3 , 8    |  V3 , 1    |  V3 , 768  |  V3 , 521  |  V3 , 386  |  V3 , 3040  |  V3 , 2150 |
      |  V4 , 3199 |  V4 , 495  |  V4 , 502  |  V4 , 265  |  V4 , 18   |  V4 , 889  |  V4 , 3543  |  V4 , 2653 |
      |  V5 , 144  |  V5 , 2560 |  V5 , 2553 |  V5 , 3320 |  V5 , 3078 |  V5 , 2166 |  V5 , 488   |  V5 , 402  |

    By sorting them we can reverse and to find the closest storages nodes.
    Table below shows the storages nodes by validation nodes

       |-----|-----|-----|-----|-----|
       | V1  | V2  | V3  | V4  | V5  |
       |-----|-----|-----|-----|-----|
       | S2  | S8  | S6  | S1  | S4  |
       | S3  |     | S10 | S13 | S5  |
       | S7  |     | S11 | S12 | S9  |
       | S14 |     |     |     | S15 |
       |     |     |     |     | S16 |
  """
  @spec tree(validation_nodes :: Node.t(), storage_nodes :: list(Node.t())) ::
          replication_tree :: map()
  def tree(validation_nodes, storage_nodes) do
    storage_nodes
    |> Enum.reduce(%{}, fn storage_node, acc ->
      storage_node_weight =
        storage_node.network_patch |> String.to_charlist() |> List.to_integer(16)

      [closest_validation_node] =
        Enum.sort_by(validation_nodes, fn validation_node ->
          validation_node_weight =
            validation_node.network_patch |> String.to_charlist() |> List.to_integer(16)

          abs(storage_node_weight - validation_node_weight)
        end)
        |> Enum.take(1)

      Map.update(
        acc,
        closest_validation_node.last_public_key,
        [storage_node],
        &(&1 ++ [storage_node])
      )
    end)
  end

  @doc """
  Starts the process of replication of the given transactions towards to next storage pool of the transaction chain, beacon chain, as well
  as the node involved inside the validations and the recipient of the transfers or smart contract.

  This replication involves the sending of the validated transaction to those differents pools.

  Once received the nodes will performed either chain validation or transaction only validation depending on their storage role
  (unspent outputs, validation nodes, chain storage nodes, beacon storage node, etc..)
  """
  @spec run(
          tx :: Transaction.validated(),
          chain_replication_nodes :: list(Node.t()),
          beacon_replication_nodes :: list(Node.t())
        ) :: :ok
  def run(
        tx = %Transaction{
          data: %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: uco_transfers
              }
            },
            recipients: recipients
          },
          validation_stamp: %ValidationStamp{
            node_movements: node_movements
          }
        },
        chain_replication_nodes,
        beacon_replication_nodes
      ) do
    Task.Supervisor.async_stream_nolink(TaskSupervisor, chain_replication_nodes, fn node ->
      P2P.send_message(node, {:replicate_chain, tx})
    end)
    |> Stream.run()

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      beacon_replication_nodes,
      &P2P.send_message(&1, {:replicate_address, tx})
    )
    |> Stream.run()

    utxo_nodes =
      [transfers_recipients(uco_transfers), recipients, rewarded_nodes(node_movements)]
      |> Enum.concat()
      |> Enum.uniq()

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      utxo_nodes,
      &P2P.send_message(&1, {:replicate_transaction, tx})
    )
    |> Stream.run()
  end

  defp transfers_recipients(transfers) do
    Enum.map(transfers, fn %Transfer{to: recipient} -> recipient end)
  end

  defp rewarded_nodes(%NodeMovements{rewards: rewards}) do
    Enum.map(rewards, fn {node, _} -> node end)
  end

  @doc """
  Checks the entire integrity of the chain by rebuilding the context of the transaction and validating:
  - Pending transaction integrity
  - Validation Stamp and Cross validation stamp integrity
  - Chain integrity
  - ARCH consensus atomic commitment
  """
  @spec chain_validation(Transaction.validated()) :: :ok | {:error, :invalid_transaction}
  def chain_validation(tx = %Transaction{}) do
    with true <- Transaction.valid_pending_transaction?(tx),
         {:ok, chain, unspent_outputs} <- check_with_context(tx),
         :ok <- verify_transaction_stamp(tx, chain, unspent_outputs) do
      {:ok, [tx | chain]}
    else
      false ->
        {:error, :invalid_transaction}

      {:error, _} = e ->
        e
    end
  end

  defp check_with_context(tx = %Transaction{}) do
    case Context.fetch(tx) do
      {[], [], _} ->
        {:ok, [], []}

      {[], unspent_outputs, _} ->
        {:ok, [], unspent_outputs}

      {chain, unspent_outputs, _} ->
        if valid_chain?([tx | chain]) do
          {:ok, chain, unspent_outputs}
        else
          {:error, :invalid_transaction}
        end
    end
  end

  defp valid_chain?(
         chain = [
           %Transaction{
             previous_public_key: previous_public_key,
             validation_stamp: %ValidationStamp{proof_of_integrity: poi}
           }
           | [%Transaction{address: previous_address} | _]
         ]
       ) do
    cond do
      ProofOfIntegrity.compute(chain) != poi ->
        false

      Crypto.hash(previous_public_key) != previous_address ->
        false

      true ->
        true
    end
  end

  @doc """
  Check the transaction only without require its chain by validating:
  - pending transaction integrity
  - validation stamp and cross validation stamp integrity
  - ARCH consensus atomic commitment.
  """
  @spec transaction_validation_only(Transaction.validated()) ::
          :ok | {:error, :invalid_transaction}
  def transaction_validation_only(
        tx = %Transaction{
          validation_stamp:
            stamp = %ValidationStamp{
              proof_of_work: pow,
              ledger_movements: ledger_movements,
              node_movements: %NodeMovements{fee: fee, rewards: rewards}
            },
          cross_validation_stamps: stamps
        }
      ) do
    {coordinator_public_key, _} = Enum.at(rewards, 1)

    with true <- Transaction.valid_pending_transaction?(tx),
         true <-
           ProofOfWork.verify?(
             tx,
             pow
           ),
         true <- Stamp.valid_cross_validation_stamps?(stamps, stamp),
         true <- Fee.compute(tx) == fee,
         # TODO: activate when the network pool will be implemented
         #  true <-
         #    Enum.reduce(rewards, 0, fn {_, amount}, acc -> acc + amount end) == fee,
         true <- ValidationStamp.valid_signature?(stamp, coordinator_public_key),
         true <- Stamp.atomic_commitment?(stamps),
         true <- pow != "",
         {_, inconsistencies, _} <- List.first(stamps),
         true <- inconsistencies == [],
         true <- ledger_movements != :unsufficient_funds do
      :ok
    else
      _reason ->
        {:error, :invalid_transaction}
    end
  end

  defp verify_transaction_stamp(
         tx = %Transaction{
           cross_validation_stamps: cross_validation_stamps,
           validation_stamp: %ValidationStamp{node_movements: %NodeMovements{rewards: rewards}}
         },
         chain,
         unspent_outputs
       ) do
    case P2P.node_info() do
      %Node{authorized?: false} ->
        {coordinator, _} = Enum.at(rewards, 1)
        cross_validators = Enum.map(cross_validation_stamps, fn {_, _, pub} -> pub end)
        do_verify_transaction_stamp(tx, chain, unspent_outputs, coordinator, cross_validators)

      _ ->
        {coordinator, cross_validators} =
          case tx
               |> Transaction.pending()
               |> Election.validation_nodes()
               |> Enum.map(& &1.last_public_key) do
            [coordinator | []] ->
              {coordinator, [coordinator]}

            [coordinator | cross_validators] ->
              {coordinator, cross_validators}
          end

        if Enum.all?(cross_validation_stamps, fn {_, _, pub} -> pub in cross_validators end) do
          do_verify_transaction_stamp(
            tx,
            chain,
            unspent_outputs,
            coordinator,
            cross_validators
          )
        else
          {:error, :invalid_transaction}
        end
    end
  end

  defp do_verify_transaction_stamp(
         tx = %Transaction{
           validation_stamp:
             stamp = %ValidationStamp{
               proof_of_work: pow,
               ledger_movements: %LedgerMovements{uco: next_uco_ledger}
             },
           cross_validation_stamps: cross_stamps
         },
         chain,
         unspent_outputs,
         coordinator,
         cross_validation_nodes
       ) do
    with true <- Stamp.valid_cross_validation_stamps?(cross_stamps, stamp),
         :ok <-
           Stamp.check_validation_stamp(
             tx,
             stamp,
             coordinator,
             cross_validation_nodes,
             chain,
             unspent_outputs
           ),
         true <- Stamp.atomic_commitment?(cross_stamps),
         true <- pow != "",
         {_, inconsistencies, _} <- List.first(cross_stamps),
         true <- inconsistencies == [],
         true <- next_uco_ledger != :unsufficient_funds do
      :ok
    else
      _reason ->
        {:error, :invalid_transaction}
    end
  end
end
