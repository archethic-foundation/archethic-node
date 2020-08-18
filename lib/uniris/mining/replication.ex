defmodule Uniris.Mining.Replication do
  @moduledoc false

  alias Uniris.Beacon
  alias Uniris.Crypto
  alias Uniris.Election

  alias Uniris.Governance

  alias Uniris.Mining.Context
  alias Uniris.Mining.Fee
  alias Uniris.Mining.ProofOfIntegrity
  alias Uniris.Mining.ProofOfWork

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.Storage

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp
  alias Uniris.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.TransactionData

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
  Determines if a chain is valid in its integrity
  """
  @spec valid_chain?([Transaction.t(), ...]) :: boolean
  def valid_chain?([
        tx = %Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: poi}}
      ]) do
    poi == ProofOfIntegrity.compute([tx])
  end

  def valid_chain?(
        chain = [
          %Transaction{
            previous_public_key: previous_public_key,
            timestamp: timestamp,
            validation_stamp: %ValidationStamp{proof_of_integrity: poi}
          }
          | [%Transaction{address: previous_address, timestamp: previous_timestamp} | _]
        ]
      ) do
    cond do
      ProofOfIntegrity.compute(chain) != poi ->
        false

      Crypto.hash(previous_public_key) != previous_address ->
        false

      DateTime.diff(timestamp, previous_timestamp, :microsecond) <= 0 ->
        false

      true ->
        true
    end
  end

  @doc """
  Verify the transaction integrity and mining including the validation stamp,
  the atomic commitment and the cross validation stamps integrity, node movements
  """
  @spec valid_transaction?(Transaction.t(), opts :: [context: Context.t()]) :: boolean()
  def valid_transaction?(_tx, opts \\ [])

  def valid_transaction?(
        tx = %Transaction{
          validation_stamp: %ValidationStamp{proof_of_work: ""}
        },
        _opts
      ) do
    Logger.error("Invalid proof of work (empty) for #{Base.encode16(tx.address)}")
    false
  end

  def valid_transaction?(
        tx = %Transaction{
          validation_stamp: %ValidationStamp{proof_of_integrity: ""}
        },
        _opts
      ) do
    Logger.error("Invalid proof of integrity (empty) for #{Base.encode16(tx.address)}")
    false
  end

  # Each transaction must at least contains a welcome node and validator reward
  def valid_transaction?(
        tx = %Transaction{
          validation_stamp: %ValidationStamp{
            ledger_operations: %LedgerOperations{node_movements: node_movements}
          }
        },
        _opts
      )
      when length(node_movements) < 2 do
    Logger.error("Invalid node movements (less than 2) for #{Base.encode16(tx.address)}")
    false
  end

  def valid_transaction?(
        tx = %Transaction{
          validation_stamp:
            stamp = %ValidationStamp{
              proof_of_work: pow,
              ledger_operations: %LedgerOperations{fee: fee, node_movements: node_movements}
            },
          cross_validation_stamps: cross_stamps
        },
        opts
      ) do
    context = Keyword.get(opts, :context)
    rewarded_nodes = Enum.map(node_movements, & &1.to)
    coordinator_public_key = Enum.at(rewarded_nodes, 1)
    total_rewards = Enum.reduce(node_movements, 0.0, &(&2 + &1.amount))
    cross_validation_nodes = Enum.map(cross_stamps, & &1.node_public_key)

    with true <- Transaction.valid_pending_transaction?(tx),
         true <- ValidationStamp.valid_signature?(stamp, coordinator_public_key),
         true <- ProofOfWork.verify?(pow, tx),
         true <- Fee.compute(tx) == fee,
         true <- total_rewards == fee,
         true <- Transaction.valid_cross_validation_stamps?(tx),
         true <- Transaction.atomic_commitment?(tx),
         true <- Enum.all?(cross_validation_nodes, &(&1 in rewarded_nodes)) do
      validation_with_context(tx, context)
    end
  end

  defp validation_with_context(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: ledger_ops
           }
         },
         %Context{previous_chain: chain, unspent_outputs: unspent_outputs}
       ) do
    if valid_chain?([tx | chain]) do
      {:ok, node_info} = P2P.node_info()

      if LedgerOperations.verify?(
           ledger_ops,
           tx,
           unspent_outputs,
           validation_nodes(node_info, tx)
         ) do
        true
      else
        Logger.error("Invalid ledger operations for #{Base.encode16(tx.address)}")
        false
      end
    else
      Logger.error("Invalid chain integrity for #{Base.encode16(tx.address)}")
      false
    end
  end

  defp validation_with_context(%Transaction{}, nil), do: true

  # Return the validation depending on the node authorization.
  # Authorized node will performs the election algorithms
  # while non authorized will get them from the node movements and cross validation stamps
  defp validation_nodes(%Node{authorized?: true}, tx) do
    case tx
         |> Transaction.to_pending()
         |> Election.validation_nodes()
         |> Enum.map(& &1.last_public_key) do
      [coordinator_node | []] ->
        [coordinator_node | [coordinator_node]]

      nodes ->
        nodes
    end
  end

  defp validation_nodes(%Node{authorized?: false}, %Transaction{
         validation_stamp: %ValidationStamp{
           ledger_operations: %LedgerOperations{node_movements: node_movements}
         },
         cross_validation_stamps: cross_validation_stamps
       }) do
    [_ | [%NodeMovement{to: coordinator_node} | _]] = node_movements
    cross_validation_nodes = Enum.map(cross_validation_stamps, & &1.node_public_key)
    [coordinator_node | cross_validation_nodes]
  end

  @spec run(Transaction.t()) :: :ok
  def run(
        tx = %Transaction{
          validation_stamp: %ValidationStamp{
            ledger_operations: ledger_ops
          }
        }
      ) do
    cond do
      Crypto.node_public_key(0) in chain_storage_nodes_keys(tx) ->
        replicate_chain(tx)

      Crypto.node_public_key(0) in io_storage_nodes_keys(ledger_ops) ->
        replicate_io(tx)

      Crypto.node_public_key(0) in beacon_storage_nodes_keys(tx) ->
        replicate_beacon(tx)

      true ->
        raise "Unexpected replication request"
    end
  end

  # Perform full verification of the transaction before chain storage including the transaction integrity,
  # the chain integrity and the cross validation stamps expectations
  defp replicate_chain(tx = %Transaction{}) do
    Logger.info("Replicate transaction chain for #{Base.encode16(tx.address)}")

    Logger.info("Fetch context for #{Base.encode16(tx.address)}")
    context = %Context{previous_chain: chain} = Context.fetch_history(%Context{}, tx)

    with true <- valid_transaction?(tx, context: context),
         :ok <- additional_verification(tx) do
      Storage.write_transaction_chain([tx | chain])

      if Crypto.node_public_key(0) in beacon_storage_nodes_keys(tx) do
        Beacon.add_transaction(tx)
      end

      additional_processing(tx)
      :ok
    else
      {:error, reason} ->
        Storage.write_ko_transaction(tx, [reason])
        Logger.info("KO transaction #{Base.encode16(tx.address)}")
    end
  end

  defp additional_verification(tx = %Transaction{type: :code_proposal}) do
    Governance.preliminary_checks(tx)
  end

  defp additional_verification(_), do: :ok

  defp additional_processing(%Transaction{
         type: :code_approval,
         data: %TransactionData{recipients: [proposal_address]}
       }) do
    approvals = Storage.get_pending_transaction_signatures(proposal_address)
    ratio = length(approvals) / length(P2P.list_nodes())

    if ratio >= Governance.code_approvals_threshold() and
         Crypto.node_public_key(0) in chain_storage_nodes_keys(proposal_address) do
      :ok = Governance.deploy_testnet(proposal_address)
    else
      :ok
    end
  end

  defp additional_processing(_), do: :ok

  # Verify the transaction integrity before to store. This method is used
  # for the replication of transaction movements (recipients unspent outputs) and node movements (rewards)
  defp replicate_io(tx) do
    if valid_transaction?(tx) do
      Storage.write_transaction(tx)

      if Crypto.node_public_key(0) in beacon_storage_nodes_keys(tx) do
        Beacon.add_transaction(tx)
      end

      :ok
    else
      Storage.write_ko_transaction(tx)
      Logger.info("KO transaction #{Base.encode16(tx.address)}")
    end
  end

  # Verify the transaction integrity before to store. This method is used
  # for the replication of transaction address towards the beacon chain
  defp replicate_beacon(tx) do
    if valid_transaction?(tx) do
      Beacon.add_transaction(tx)
    else
      Storage.write_ko_transaction(tx)
      Logger.info("KO transaction #{Base.encode16(tx.address)}")
    end
  end

  def chain_storage_nodes_keys(%Transaction{type: txType, address: address}) do
    if Transaction.network_type?(txType) do
      P2P.list_nodes()
      |> Enum.filter(& &1.ready?)
      |> Enum.map(& &1.first_public_key)
    else
      address
      |> Election.storage_nodes()
      |> Enum.map(& &1.first_public_key)
    end
  end

  def chain_storage_nodes_keys(address) do
    address
    |> Election.storage_nodes()
    |> Enum.map(& &1.first_public_key)
  end

  def io_storage_nodes_keys(ops = %LedgerOperations{}) do
    ops
    |> LedgerOperations.io_storage_nodes()
    |> Enum.map(& &1.first_public_key)
  end

  defp beacon_storage_nodes_keys(%Transaction{address: address, timestamp: timestamp}) do
    address
    |> Beacon.subset_from_address()
    |> Beacon.get_pool(timestamp)
    |> Enum.map(& &1.first_public_key)
  end
end
