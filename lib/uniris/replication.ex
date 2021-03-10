defmodule Uniris.Replication do
  @moduledoc """
  Uniris replication algorithms are based on a replication tree during the transaction mining
  and include several kind of roles: chain storage nodes, beacon storage nodes, I/O storage node.

  From this, different validation and storage mechanisms are used.

  Moreover because Uniris supports network transaction to constantly enhanced the system,
  those transactions will be loaded into the subsystems (Node, Shared Secrets, Governance, etc..)
  """

  alias Uniris.Account

  alias Uniris.BeaconChain

  alias Uniris.Contracts

  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Message.AcknowledgeStorage
  alias Uniris.P2P.Message.NotifyLastTransactionAddress
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node

  alias Uniris.OracleChain

  alias Uniris.SharedSecrets

  alias __MODULE__.TransactionContext
  alias __MODULE__.TransactionValidator

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Uniris.Utils

  @type role :: :chain | :IO | :beacon

  @type nodes_by_roles :: [
          chain: list(Node.t()),
          beacon: list(Node.t()),
          IO: list(Node.t())
        ]

  require Logger

  @doc """
  Process transaction replication by validating the transaction and process it depending on the storage node role
  - Chain storage nodes: will download the transaction chain and unspent outputs, ensure the entire correctness and persist a new transaction chain
  - Beacon chain storage: will verify the transaction integrity and will store the transaction in the beacon chain
  - IO storage node: will verify the transaction integrity and store the transaction

  Once the transaction is stored, the transaction is loaded into the system,
  so for instance if the transaction is a network transaction, a dedicated behavior will be applied
  - Node: Identification of a a new node or a node update
  - Node Shared Secrets: schedule of the node shared secret renewal
  - Origin Shared Secrets: load the new origin public keys
  - Code Approval: manage approvals of code proposals

  Options:
  - ack_storage?: Determines if the storage node must notify the welcome node about the replication
  - self_repair?: Determines if the replication is from a self repair cycle. This switch will be determine to fetch unspent outputs or transaction inputs for a chain role validation
  """
  @spec process_transaction(
          validated_tx :: Transaction.t(),
          role_list :: list(role()),
          options :: [ack_storage?: boolean(), self_repair?: boolean()]
        ) ::
          :ok | {:error, :invalid_transaction}
  def process_transaction(tx = %Transaction{}, roles, opts \\ [])
      when is_list(roles) and is_list(opts) do
    if :chain in roles do
      do_process_transaction_as_chain_storage_node(tx, roles, opts)
    else
      do_process_transaction(tx, roles, opts)
    end
  end

  defp do_process_transaction_as_chain_storage_node(
         tx = %Transaction{address: address, type: type},
         roles,
         opts
       ) do
    ack_storage? = Keyword.get(opts, :ack_storage?, false)
    self_repair? = Keyword.get(opts, :self_repair?, false)

    Logger.info("Replication started", transaction: "#{type}@#{Base.encode16(address)}")

    Logger.info("Retrieve chain and unspent outputs...",
      transaction: "#{type}@#{Base.encode16(address)}"
    )

    {chain, inputs_unspent_outputs} = fetch_context(tx, self_repair?)

    Logger.info("Size of the chain retrieved: #{Enum.count(chain)}",
      transaction: "#{type}@#{Base.encode16(address)}"
    )

    case TransactionValidator.validate(
           tx,
           Enum.at(chain, 0),
           Enum.to_list(inputs_unspent_outputs),
           self_repair?
         ) do
      :ok ->
        :ok = TransactionChain.write(Stream.concat([tx], chain))
        :ok = ingest_transaction(tx)

        if :beacon in roles do
          BeaconChain.add_transaction_summary(tx)
        end

        if ack_storage? do
          :ok = acknowledge_storage(tx)
        else
          :ok
        end

      {:error, reason} ->
        :ok = TransactionChain.write_ko_transaction(tx)

        Logger.error("Invalid transaction for replication - #{inspect(reason)}",
          transaction: "#{type}@#{Base.encode16(address)}"
        )

        {:error, :invalid_transaction}
    end
  end

  defp do_process_transaction(tx = %Transaction{address: address, type: type}, roles, opts)
       when is_list(roles) do
    self_repair? = Keyword.get(opts, :self_repair?, false)
    Logger.info("Replication started", transaction: "#{type}@#{Base.encode16(address)}")

    case TransactionValidator.validate(tx, self_repair?) do
      :ok ->
        if :IO in roles do
          :ok = TransactionChain.write_transaction(tx)
          ingest_transaction(tx)
        end

        if :beacon in roles do
          BeaconChain.add_transaction_summary(tx)
        end

        :ok

      {:error, reason} ->
        :ok = TransactionChain.write_ko_transaction(tx)

        Logger.error("Invalid transaction for replication - #{inspect(reason)}",
          transaction: "#{type}@#{Base.encode16(address)}"
        )

        {:error, :invalid_transaction}
    end
  end

  defp fetch_context(tx = %Transaction{type: type, timestamp: timestamp}, self_repair?) do
    prev_address = Transaction.previous_address(tx)

    if Transaction.network_type?(type) do
      do_fetch_context_for_network_transaction(prev_address, timestamp, self_repair?)
    else
      fetch_context_for_regular_transaction(prev_address, timestamp, self_repair?)
    end
  end

  defp do_fetch_context_for_network_transaction(previous_address, timestamp, self_repair?) do
    previous_chain = TransactionChain.get(previous_address)

    inputs_unspent_outputs =
      fetch_inputs_unspent_outputs(previous_address, timestamp, self_repair?)

    {previous_chain, inputs_unspent_outputs}
  end

  defp fetch_context_for_regular_transaction(previous_address, timestamp, self_repair?) do
    [{%Task{}, {:ok, previous_chain}}, {%Task{}, {:ok, inputs_unspent_outputs}}] =
      Task.yield_many([
        Task.async(fn -> TransactionContext.fetch_transaction_chain(previous_address) end),
        Task.async(fn ->
          fetch_inputs_unspent_outputs(previous_address, timestamp, self_repair?)
        end)
      ])

    {previous_chain, inputs_unspent_outputs}
  end

  defp fetch_inputs_unspent_outputs(previous_address, timestamp, _self_repair = true) do
    TransactionContext.fetch_transaction_inputs(previous_address, timestamp)
  end

  defp fetch_inputs_unspent_outputs(previous_address, _timestamp, _self_repair = false) do
    TransactionContext.fetch_unspent_outputs(previous_address)
  end

  @doc """
  Send an acknowledgment of the replication of the transaction to the welcome node and the previous storage pool
  """
  @spec acknowledge_storage(Transaction.t()) :: :ok
  def acknowledge_storage(tx = %Transaction{address: tx_address}) do
    Task.start(fn -> notify_welcome_node(tx) end)

    Task.start(fn ->
      acknowledge_previous_storage_nodes(tx_address, Transaction.previous_address(tx))
    end)

    :ok
  end

  defp notify_welcome_node(%Transaction{
         address: address,
         validation_stamp: %ValidationStamp{
           ledger_operations: %LedgerOperations{node_movements: node_movements}
         }
       }) do
    %Ok{} =
      node_movements
      |> Enum.find(&(:welcome_node in &1.roles))
      |> Map.get(:to)
      |> P2P.get_node_info!()
      |> P2P.send_message!(%AcknowledgeStorage{address: address})

    :ok
  end

  @doc """
  Notify the previous storage pool than a new transaction on the chain is present
  """
  @spec acknowledge_previous_storage_nodes(binary(), binary()) :: :ok
  def acknowledge_previous_storage_nodes(address, previous_address)
      when is_binary(address) and is_binary(previous_address) do
    TransactionChain.register_last_address(previous_address, address)
    Contracts.stop_contract(previous_address)

    if previous_address != address do
      case TransactionChain.get_transaction(previous_address, [:previous_public_key]) do
        {:ok, tx} ->
          next_previous_address = Transaction.previous_address(tx)

          if previous_address != next_previous_address do
            previous_storage_nodes =
              chain_storage_nodes(next_previous_address, P2P.list_nodes(availability: :global))

            if Utils.key_in_node_list?(previous_storage_nodes, Crypto.node_public_key(0)) do
              acknowledge_previous_storage_nodes(address, next_previous_address)
            else
              P2P.broadcast_message(previous_storage_nodes, %NotifyLastTransactionAddress{
                address: address,
                previous_address: next_previous_address
              })
            end
          end

        _ ->
          :ok
      end
    else
      :ok
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
      iex> storage_nodes = [
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
      iex> Replication.generate_tree(validation_nodes, storage_nodes)
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
  @spec ingest_transaction(Transaction.t()) :: :ok
  def ingest_transaction(tx = %Transaction{}) do
    TransactionChain.load_transaction(tx)
    Crypto.load_transaction(tx)
    P2P.load_transaction(tx)
    SharedSecrets.load_transaction(tx)
    Account.load_transaction(tx)
    Contracts.load_transaction(tx)
    BeaconChain.load_transaction(tx)
    OracleChain.load_transaction(tx)
    :ok
  end

  @spec chain_storage_node?(Transaction.t(), Crypto.key(), list(Node.t())) :: boolean()
  def chain_storage_node?(
        %Transaction{address: address, type: type},
        public_key,
        node_list \\ P2P.list_nodes(availability: :global)
      ) do
    address
    |> chain_storage_nodes(type, node_list)
    |> Utils.key_in_node_list?(public_key)
  end

  @spec beacon_storage_node?(Transaction.t(), Crypto.key(), list(Node.t())) :: boolean()
  def beacon_storage_node?(
        %Transaction{address: address, timestamp: timestamp},
        public_key,
        node_list \\ P2P.list_nodes(availability: :global)
      ) do
    address
    |> beacon_storage_nodes(timestamp, node_list)
    |> Utils.key_in_node_list?(public_key)
  end

  @spec io_storage_node?(Transaction.t(), Crypto.key(), list(Node.t())) :: boolean()
  def io_storage_node?(
        %Transaction{validation_stamp: %ValidationStamp{ledger_operations: ops}},
        public_key,
        node_list \\ P2P.list_nodes(availability: :global)
      ) do
    ops
    |> io_storage_nodes(node_list)
    |> Utils.key_in_node_list?(public_key)
  end

  @doc """
  Return the storage nodes for the transaction chain based on the transaction address, the transaction type and set a nodes
  """
  @spec chain_storage_nodes(binary(), Transaction.transaction_type(), list(Node.t())) ::
          list(Node.t())
  def chain_storage_nodes(address, type, node_list)
      when is_binary(address) and is_atom(type) and is_list(node_list) do
    if Transaction.network_type?(type) do
      node_list
    else
      chain_storage_nodes(address, node_list)
    end
  end

  @doc """
  Return the storage nodes for the transaction chain based on the transaction address and set a nodes
  """
  @spec chain_storage_nodes(binary(), list(Node.t())) :: list(Node.t())
  def chain_storage_nodes(address, node_list) when is_binary(address) and is_list(node_list) do
    Election.storage_nodes(address, node_list, Election.get_storage_constraints())
  end

  @doc """
  Return the storage nodes for the transaction IO based on the `LedgerOperations` and a set of nodes
  """
  @spec io_storage_nodes(LedgerOperations.t(), list(Node.t())) :: list(Node.t())
  def io_storage_nodes(
        operations = %LedgerOperations{},
        node_list \\ P2P.list_nodes(availability: :global)
      ) do
    operations
    |> LedgerOperations.movement_addresses()
    |> Election.io_storage_nodes(node_list, Election.get_storage_constraints())
  end

  @doc """
  Return the beacon storage nodes for the transaction based on the transaction address, transaction datetime and a set of nodes
  """
  @spec beacon_storage_nodes(binary(), DateTime.t(), list(Node.t())) :: list(Node.t())
  def beacon_storage_nodes(
        address,
        timestamp = %DateTime{},
        node_list \\ P2P.list_nodes(availability: :global)
      )
      when is_binary(address) and is_list(node_list) do
    subset = BeaconChain.subset_from_address(address)
    slot_time = BeaconChain.next_slot(timestamp)

    Election.beacon_storage_nodes(
      subset,
      slot_time,
      node_list,
      Election.get_storage_constraints()
    )
  end
end
