defmodule Archethic.Replication do
  @moduledoc """
  Archethic replication algorithms are based on a replication tree during the transaction mining
  and include several kind of roles: chain storage nodes, beacon storage nodes, I/O storage node.

  From this, different validation and storage mechanisms are used.

  Moreover because Archethic supports network transaction to constantly enhanced the system,
  those transactions will be loaded into the subsystems (Node, Shared Secrets, Governance, etc..)
  """

  alias __MODULE__.TransactionContext
  alias __MODULE__.TransactionPool
  alias __MODULE__.TransactionValidator
  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.Governance
  alias Archethic.Mining.Error
  alias Archethic.Mining.ValidationContext
  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.NotifyLastTransactionAddress
  alias Archethic.P2P.Node
  alias Archethic.PubSub
  alias Archethic.Reward
  alias Archethic.SelfRepair.NetworkView
  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.Utils
  alias Archethic.UTXO

  require Logger

  @doc """
  Validate the transaction before to replicate as chain storage nodes

  It will download the transaction chain and unspents to validate the new transaction and store the new transaction in the pool awaiting commitment
  """
  @spec validate_transaction(
          tx :: Transaction.t(),
          contract_context :: nil | Contract.Context.t(),
          validation_inputs :: list(VersionedUnspentOutput.t())
        ) :: :ok | {:error, Error.t()}
  def validate_transaction(
        tx = %Transaction{
          address: address,
          type: type,
          validation_stamp: validation_stamp = %ValidationStamp{timestamp: validation_time}
        },
        contract_context,
        validation_inputs
      ) do
    start_time = System.monotonic_time()

    Logger.info("Replication validation started",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    {genesis_address, previous_tx, inputs, resolved_addresses} = fetch_context(tx)

    validation_context = %ValidationContext{
      transaction: tx,
      resolved_addresses: resolved_addresses,
      contract_context: contract_context,
      aggregated_utxos: validation_inputs,
      unspent_outputs: inputs,
      validation_time: validation_time,
      validation_stamp: validation_stamp,
      previous_transaction: previous_tx,
      genesis_address: genesis_address
    }

    case TransactionValidator.validate(validation_context) do
      %ValidationContext{mining_error: nil} ->
        Logger.info("Replication validation finished",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        :telemetry.execute(
          [:archethic, :replication, :validation],
          %{
            duration: System.monotonic_time() - start_time
          },
          %{role: :chain}
        )

      %ValidationContext{mining_error: error} ->
        :ok = TransactionChain.write_ko_transaction(tx)

        Logger.warning("Invalid transaction for replication - #{inspect(error)}",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        {:error, error}
    end
  end

  @doc """
  Push a new transaction in the transaction pool awaiting atomic commitment
  """
  @spec add_transaction_to_commit_pool(Transaction.t(), list(VersionedUnspentOutput.t())) :: :ok
  defdelegate add_transaction_to_commit_pool(tx, inputs),
    to: TransactionPool,
    as: :add_transaction

  @doc """
  Pop a registered transaction in the pool awaiting atomic commitment
  """
  @spec get_transaction_in_commit_pool(binary()) ::
          {:ok, Transaction.t(), list(VersionedUnspentOutput.t())}
          | {:error, :transaction_not_exists}
  defdelegate get_transaction_in_commit_pool(address), to: TransactionPool, as: :pop_transaction

  @type sync_options :: [self_repair?: boolean(), resolved_addresses: map(), chain?: boolean()]

  @doc """
  Replicate and store the transaction chain from the transaction cached in the pool
  """
  @spec sync_transaction_chain(
          tx :: Transaction.t(),
          genesis_address :: Crypto.prepended_hash(),
          nodes :: list(Node.t()),
          opts :: sync_options()
        ) :: :ok
  def sync_transaction_chain(
        tx = %Transaction{
          address: address,
          type: type,
          validation_stamp: %ValidationStamp{timestamp: timestamp}
        },
        genesis_address,
        download_nodes \\ P2P.authorized_and_available_nodes(),
        opts \\ []
      ) do
    start_time = System.monotonic_time()

    # Stream the insertion of the chain
    first_node_key = Crypto.first_node_public_key()

    ingest_opts =
      Keyword.put(opts, :io_transaction?, false) |> Keyword.put(:download_nodes, download_nodes)

    tx
    |> stream_previous_chain(genesis_address, download_nodes)
    |> Stream.each(fn tx = %Transaction{address: address, type: type} ->
      TransactionChain.write_transaction(tx)

      # There is some case where a transaction is not replicated while it should
      # because of some latency or network issue. So when we replicate a past chain
      # we also ingest the transaction if we are storage node of it

      ingest? =
        Transaction.network_type?(type) or
          Election.chain_storage_node?(address, first_node_key, download_nodes) or
          Election.chain_storage_node?(genesis_address, first_node_key, download_nodes)

      opts = Keyword.delete(ingest_opts, :resolved_addresses)
      if ingest?, do: ingest_transaction(tx, genesis_address, opts)
    end)
    |> Stream.run()

    TransactionChain.write_transaction(tx)

    :ok = ingest_transaction(tx, genesis_address, ingest_opts)

    Logger.info("Replication finished",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    PubSub.notify_new_transaction(address, type, timestamp)

    :telemetry.execute(
      [:archethic, :replication, :full_write],
      %{
        duration: System.monotonic_time() - start_time
      }
    )

    :ok
  end

  @doc """
  Process a new transaction replication for the I/O chains.

  It will validate the new transaction and store the new transaction updating then the internals ledgers and views
  """
  @spec validate_and_store_transaction(
          tx :: Transaction.t(),
          genesis_address :: Crypto.prepended_hash(),
          opts :: sync_options()
        ) :: :ok | {:error, Error.t()}
  def validate_and_store_transaction(
        tx = %Transaction{
          address: address,
          type: type,
          validation_stamp: stamp = %ValidationStamp{timestamp: validation_time}
        },
        genesis_address,
        opts \\ []
      )
      when is_list(opts) do
    chain? = Keyword.get(opts, :chain?, false)

    transaction_exists? =
      if chain?,
        do: TransactionChain.transaction_exists?(address),
        else: TransactionChain.transaction_exists?(address, :io)

    if transaction_exists? do
      Logger.warning("Transaction already exists",
        transaction_address: Base.encode16(address),
        transaction_type: type
      )

      {:error, Error.new(:invalid_pending_transaction, "Transaction already exists")}
    else
      start_time = System.monotonic_time()

      Logger.info("Replication transaction started",
        transaction_address: Base.encode16(address),
        transaction_type: type
      )

      context = %ValidationContext{
        transaction: tx,
        validation_stamp: stamp,
        validation_time: validation_time
      }

      case TransactionValidator.validate_consensus(context) do
        %ValidationContext{mining_error: nil} ->
          :telemetry.execute(
            [:archethic, :replication, :validation],
            %{
              duration: System.monotonic_time() - start_time
            },
            %{role: :IO}
          )

          if chain?,
            do: sync_transaction_chain(tx, genesis_address),
            else: synchronize_io_transaction(tx, genesis_address, opts)

        %ValidationContext{mining_error: error} ->
          :ok = TransactionChain.write_ko_transaction(tx)

          Logger.warning("Invalid transaction for replication - #{inspect(error)}",
            transaction_address: Base.encode16(address),
            transaction_type: type
          )

          {:error, error}
      end
    end
  end

  @doc """
  Synchronize an io transaction into DB an memory table
  """
  @spec synchronize_io_transaction(
          tx :: Transaction.t(),
          genesis_address :: Crypto.prepended_hash(),
          opts :: sync_options()
        ) :: :ok
  def synchronize_io_transaction(
        tx = %Transaction{
          address: address,
          type: type,
          validation_stamp: %ValidationStamp{timestamp: timestamp}
        },
        genesis_address,
        opts \\ []
      )
      when is_list(opts) do
    :ok = TransactionChain.write_transaction(tx, :io)
    ingest_transaction(tx, genesis_address, Keyword.put(opts, :io_transaction?, true))

    Logger.info("Replication finished",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    PubSub.notify_new_transaction(address, type, timestamp)
  end

  defp fetch_context(tx = %Transaction{}) do
    previous_address = Transaction.previous_address(tx)

    Logger.debug(
      "Try to fetch previous transaction (#{Base.encode16(previous_address)})",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    genesis_task =
      Task.Supervisor.async(Archethic.task_supervisors(), fn ->
        fetch_opts =
          if TransactionChain.first_transaction?(tx),
            do: [],
            else: [acceptance_resolver: :accept_different_genesis]

        TransactionContext.fetch_genesis_address(previous_address, fetch_opts)
      end)

    previous_transaction_task =
      Task.Supervisor.async(Archethic.task_supervisors(), fn ->
        fetch_opts =
          if TransactionChain.first_transaction?(tx),
            do: [],
            else: [acceptance_resolver: :accept_transaction]

        TransactionContext.fetch_transaction(previous_address, fetch_opts)
      end)

    resolved_addresses_task =
      Task.Supervisor.async(Archethic.task_supervisors(), fn ->
        TransactionChain.resolve_transaction_addresses!(tx)
      end)

    genesis_address = Task.await(genesis_task)

    unspent_outputs = fetch_unspent_outputs(tx, genesis_address)

    [previous_transaction, resolved_addresses] =
      Task.await_many(
        [previous_transaction_task, resolved_addresses_task],
        Message.get_max_timeout() + 1000
      )

    Logger.debug("Previous transaction #{inspect(previous_transaction)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    {genesis_address, previous_transaction, unspent_outputs, resolved_addresses}
  end

  defp fetch_unspent_outputs(%Transaction{address: address, type: type}, genesis_address) do
    Logger.debug(
      "Fetch inputs for #{Base.encode16(genesis_address)}",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    genesis_address
    |> TransactionContext.fetch_transaction_unspent_outputs()
    |> tap(fn inputs ->
      Logger.debug("Got #{inspect(inputs)} for #{Base.encode16(genesis_address)}",
        transaction_address: Base.encode16(address),
        type: type
      )
    end)
  end

  defp stream_previous_chain(tx, genesis_address, download_nodes) do
    previous_address = Transaction.previous_address(tx)

    if TransactionChain.transaction_exists?(previous_address),
      do: [],
      else:
        TransactionContext.stream_transaction_chain(
          genesis_address,
          previous_address,
          download_nodes
        )
  end

  @doc """
  Notify the previous storage nodes than a new transaction on the chain is present
  """
  @spec acknowledge_previous_storage_nodes(address :: binary()) :: :ok
  def acknowledge_previous_storage_nodes(address) when is_binary(address) do
    case TransactionChain.get_genesis_address(address) do
      ^address ->
        # No transaction chain found as the DB request return the argument if not found.
        :ok

      genesis_address ->
        last_storage_nodes =
          Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

        {:ok, tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}}} =
          TransactionChain.get_transaction(address, [
            :previous_public_key,
            validation_stamp: [:timestamp]
          ])

        previous_address = Transaction.previous_address(tx)

        # Send a message to all the previous storage nodes
        genesis_address
        |> TransactionChain.list_chain_addresses()
        |> Stream.concat([{genesis_address, nil}])
        |> Stream.flat_map(fn {address, _} ->
          Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())
        end)
        |> Enum.uniq_by(& &1.first_public_key)
        |> Enum.reject(&Utils.key_in_node_list?(last_storage_nodes, &1.first_public_key))
        |> P2P.broadcast_message(%NotifyLastTransactionAddress{
          last_address: address,
          genesis_address: genesis_address,
          timestamp: timestamp,
          previous_address: previous_address
        })
    end
  end

  @doc """
  Generate a replication tree from a list of storage nodes and validation nodes by grouping
  the closest nodes by the shorter path.

  ## Rationale

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
      | S14 | S8  | S6  | S1  | S4  |
      | S7  | S13 | S11 | S10 | S9  |
      | S2  | S5  | S3  | S12 | S15 |
      |     |     |     |     | S16 |


  ## Examples

      iex> validation_nodes = [
      ...>   %Node{network_patch: "AC2", last_public_key: "key_v1"},
      ...>   %Node{network_patch: "DF3", last_public_key: "key_v2"},
      ...>   %Node{network_patch: "C22", last_public_key: "key_v3"},
      ...>   %Node{network_patch: "E19", last_public_key: "key_v4"},
      ...>   %Node{network_patch: "22A", last_public_key: "key_v5"}
      ...> ]
      ...> 
      ...> storage_nodes = [
      ...>   %Node{network_patch: "F36", first_public_key: "key_S1", last_public_key: "key_S1"},
      ...>   %Node{network_patch: "A23", first_public_key: "key_S2", last_public_key: "key_S2"},
      ...>   %Node{network_patch: "B43", first_public_key: "key_S3", last_public_key: "key_S3"},
      ...>   %Node{network_patch: "2A9", first_public_key: "key_S4", last_public_key: "key_S4"},
      ...>   %Node{network_patch: "143", first_public_key: "key_S5", last_public_key: "key_S5"},
      ...>   %Node{network_patch: "BB2", first_public_key: "key_S6", last_public_key: "key_S6"},
      ...>   %Node{network_patch: "A63", first_public_key: "key_S7", last_public_key: "key_S7"},
      ...>   %Node{network_patch: "D32", first_public_key: "key_S8", last_public_key: "key_S8"},
      ...>   %Node{network_patch: "19A", first_public_key: "key_S9", last_public_key: "key_S9"},
      ...>   %Node{network_patch: "C2A", first_public_key: "key_S10", last_public_key: "key_S10"},
      ...>   %Node{network_patch: "C23", first_public_key: "key_S11", last_public_key: "key_S11"},
      ...>   %Node{network_patch: "F22", first_public_key: "key_S12", last_public_key: "key_S12"},
      ...>   %Node{network_patch: "E2B", first_public_key: "key_S13", last_public_key: "key_S13"},
      ...>   %Node{network_patch: "AA0", first_public_key: "key_S14", last_public_key: "key_S14"},
      ...>   %Node{network_patch: "042", first_public_key: "key_S15", last_public_key: "key_S15"},
      ...>   %Node{network_patch: "3BC", first_public_key: "key_S16", last_public_key: "key_S16"}
      ...> ]
      ...> 
      ...> Replication.generate_tree(validation_nodes, storage_nodes)
      %{
        "key_v1" => [
          %Node{first_public_key: "key_S14", last_public_key: "key_S14", network_patch: "AA0"},
          %Node{first_public_key: "key_S7", last_public_key: "key_S7", network_patch: "A63"},
          %Node{first_public_key: "key_S2", last_public_key: "key_S2", network_patch: "A23"}
        ],
        "key_v2" => [
          %Node{first_public_key: "key_S13", last_public_key: "key_S13", network_patch: "E2B"},
          %Node{first_public_key: "key_S8", last_public_key: "key_S8", network_patch: "D32"},
          %Node{first_public_key: "key_S5", last_public_key: "key_S5", network_patch: "143"}
        ],
        "key_v3" => [
          %Node{first_public_key: "key_S11", last_public_key: "key_S11", network_patch: "C23"},
          %Node{first_public_key: "key_S6", last_public_key: "key_S6", network_patch: "BB2"},
          %Node{first_public_key: "key_S3", last_public_key: "key_S3", network_patch: "B43"}
        ],
        "key_v4" => [
          %Node{first_public_key: "key_S12", last_public_key: "key_S12", network_patch: "F22"},
          %Node{first_public_key: "key_S10", last_public_key: "key_S10", network_patch: "C2A"},
          %Node{first_public_key: "key_S1", last_public_key: "key_S1", network_patch: "F36"}
        ],
        "key_v5" => [
          %Node{first_public_key: "key_S16", last_public_key: "key_S16", network_patch: "3BC"},
          %Node{first_public_key: "key_S15", last_public_key: "key_S15", network_patch: "042"},
          %Node{first_public_key: "key_S9", last_public_key: "key_S9", network_patch: "19A"},
          %Node{first_public_key: "key_S4", last_public_key: "key_S4", network_patch: "2A9"}
        ]
      }
  """
  @spec generate_tree(validation_nodes :: list(Node.t()), storage_nodes :: list(Node.t())) ::
          replication_tree :: map()
  def generate_tree(validation_nodes, storage_nodes) do
    storage_nodes
    |> Enum.reduce(%{}, fn storage_node, tree_acc ->
      %Node{last_public_key: validation_node_key} =
        find_closest_validation_node(tree_acc, storage_node, validation_nodes)

      Map.update(tree_acc, validation_node_key, [storage_node], &[storage_node | &1])
    end)
  end

  defp find_closest_validation_node(tree, storage_node, validation_nodes) do
    {closest_validation_node, _} =
      validation_nodes
      # Get the number of replicas by nodes
      |> Enum.reduce(%{}, &Map.put(&2, &1, tree_sub_size(tree, &1.last_public_key)))
      # Sort each validation nodes by its network patch from the storage node network patch
      |> Enum.sort_by(fn {validation_node, _} ->
        sort_closest_node(validation_node, storage_node)
      end)
      # Balance the validation nodes load to find the closest nodes with the less nodes to replicate
      |> Enum.min(&sort_by_less_load/2, fn -> 0 end)

    closest_validation_node
  end

  defp tree_sub_size(tree, public_key) do
    length(Map.get(tree, public_key, []))
  end

  defp sort_by_less_load({_node_a, nb_replicas_a}, {_node_b, nb_replicas_b}),
    do: nb_replicas_a <= nb_replicas_b

  defp sort_closest_node(validation_node, storage_node) do
    validation_weight = Node.get_network_patch_num(validation_node)
    storage_weight = Node.get_network_patch_num(storage_node)
    abs(storage_weight - validation_weight)
  end

  @type ingest_options :: [
          io_transaction?: boolean(),
          self_repair?: boolean(),
          resolved_addresses: map(),
          download_nodes: list(Node.t())
        ]

  @doc """
  Ingest the transaction into system delaying the network to several handlers.

  Most of the application contexts allow the transaction loading/ingestion.
  Some transaction some have an impact the memory state or behaviors. For instance:
  - Node transaction increments the number of node keys
  - Node shared secrets transaction increments the number of node shared keys and can authorize new nodes
  - Transactions mutates the account ledgers
  - Update P2P view
  - Transactions with smart contract deploy instances of them or can put in pending state waiting approval signatures
  - Code approval transactions may trigger the TestNets deployments or hot-reloads
  """
  @spec ingest_transaction(
          tx :: Transaction.t(),
          genesis_address :: Crypto.prepended_hash(),
          opts :: ingest_options()
        ) :: :ok
  def ingest_transaction(tx = %Transaction{}, genesis_address, opts \\ []) when is_list(opts) do
    self_repair? = Keyword.get(opts, :self_repair?, false)
    resolved_addresses = Keyword.get(opts, :resolved_addresses, %{})
    download_nodes = Keyword.get(opts, :download_nodes, P2P.authorized_and_available_nodes())

    # There's currently no usage of the pending mem tables for transactions, so we comment it for now
    # TransactionChain.load_transaction(tx)
    Crypto.load_transaction(tx)
    P2P.load_transaction(tx)
    SharedSecrets.load_transaction(tx)

    UTXO.load_transaction(tx, genesis_address,
      resolved_addresses: resolved_addresses,
      download_nodes: download_nodes
    )

    Contracts.load_transaction(tx, genesis_address,
      execute_contract?: not self_repair?,
      download_nodes: download_nodes
    )

    OracleChain.load_transaction(tx)
    Reward.load_transaction(tx)
    Governance.load_transaction(tx)

    if Archethic.up?() do
      # this module will automatically update its state at the end of bootstrap self repair
      NetworkView.load_transaction(tx)
    end

    :ok
  end
end
