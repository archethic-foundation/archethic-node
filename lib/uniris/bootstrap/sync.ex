defmodule Uniris.Bootstrap.Sync do
  @moduledoc false

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.Slot.NodeInfo

  alias Uniris.Bootstrap.NetworkInit
  alias Uniris.Bootstrap.TransactionHandler

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.AddNodeInfo
  alias Uniris.P2P.Message.BootstrappingNodes
  alias Uniris.P2P.Message.EncryptedStorageNonce
  alias Uniris.P2P.Message.GetBootstrappingNodes
  alias Uniris.P2P.Message.GetStorageNonce
  alias Uniris.P2P.Message.ListNodes
  alias Uniris.P2P.Message.NodeList
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain

  require Logger

  @out_of_sync_date_threshold Application.compile_env(:uniris, [
                                __MODULE__,
                                :out_of_sync_date_threshold
                              ])

  @doc """
  Determines if network should be initialized
  """
  @spec should_initialize_network?(list(Node.t())) :: boolean()
  def should_initialize_network?([]) do
    TransactionChain.count_transactions_by_type(:node_shared_secrets) == 0
  end

  def should_initialize_network?([%Node{first_public_key: node_key}]) do
    node_key == Crypto.node_public_key(0) and
      TransactionChain.count_transactions_by_type(:node_shared_secrets) == 0
  end

  def should_initialize_network?(_), do: false

  @doc """
  Determines if the node requires an update
  """
  @spec require_update?(:inet.ip_address(), :inet.port_number(), DateTime.t()) :: boolean()
  def require_update?(ip, port, last_sync_date) do
    first_node_public_key = Crypto.node_public_key(0)

    case P2P.list_nodes() do
      [%Node{first_public_key: ^first_node_public_key}] ->
        false

      _ ->
        diff_sync = DateTime.diff(DateTime.utc_now(), last_sync_date, :second)

        case P2P.get_node_info(first_node_public_key) do
          # TODO: change the diff sync parameter when the self repair will be moved to daily
          {:ok, %Node{ip: prev_ip, port: prev_port}}
          when ip != prev_ip or port != prev_port or diff_sync > @out_of_sync_date_threshold ->
            true

          _ ->
            false
        end
    end
  end

  @doc """
  Initialize the network by predefining the storage nonce, the first node transaction and the first node shared secrets and the genesis fund allocations
  """
  @spec initialize_network(:inet.ip_address(), :inet.port_number()) :: :ok
  def initialize_network(ip, port) do
    NetworkInit.create_storage_nonce()

    Logger.info("Create first node transaction")
    tx = TransactionHandler.create_node_transaction(ip, port)

    tx
    |> NetworkInit.self_validation!()
    |> NetworkInit.self_replication()

    P2P.set_node_globally_available(Crypto.node_public_key(0))

    network_pool_seed = :crypto.strong_rand_bytes(32)
    NetworkInit.init_node_shared_secrets_chain(network_pool_seed)

    {pub, _} = Crypto.derive_keypair(network_pool_seed, 0)
    network_pool_address = Crypto.hash(pub)
    NetworkInit.init_genesis_wallets(network_pool_address)
  end

  @doc """
  Fetch and load the nodes list
  """
  @spec load_node_list(Node.t()) :: :ok
  def load_node_list(node = %Node{}) do
    %NodeList{nodes: nodes} = P2P.send_message(node, %ListNodes{})
    Enum.each(nodes, &P2P.add_node/1)
    Logger.info("Node list refreshed")
  end

  @doc """
  Fetch and load the storage nonce
  """
  @spec load_storage_nonce(Node.t()) :: :ok
  def load_storage_nonce(node = %Node{}) do
    message = %GetStorageNonce{public_key: Crypto.node_public_key()}

    %EncryptedStorageNonce{digest: encrypted_nonce} = P2P.send_message(node, message)

    :ok = Crypto.decrypt_and_set_storage_nonce(encrypted_nonce)
    Logger.info("Storage nonce set")
  end

  @doc """
  Fetch the closest nodes and new bootstrapping seeds.

  The new bootstrapping seeds are loaded and flushed for the next bootstrap.

  The closest nodes and the bootstrapping seeds are loaded into the P2P view

  Returns the closest nodes
  """
  @spec get_closest_nodes_and_renew_seeds(list(Node.t()), binary()) :: list(Node.t())
  def get_closest_nodes_and_renew_seeds(bootstrapping_seeds, patch) do
    %BootstrappingNodes{closest_nodes: closest_nodes, new_seeds: new_seeds} =
      bootstrapping_seeds
      |> P2P.broadcast_message(%GetBootstrappingNodes{patch: patch})
      |> Enum.at(0)

    :ok = P2P.new_bootstrapping_seeds(new_seeds)
    Logger.info("Bootstrapping seeds list refreshed")

    (new_seeds ++ closest_nodes)
    |> P2P.distinct_nodes()
    |> Enum.each(&P2P.add_node/1)

    Logger.info("Closest nodes and seeds loaded in the P2P view")

    closest_nodes
  end

  @doc """
  Notify the beacon chain for the first node public key about the readiness of the node and the end of the bootstrapping
  """
  @spec publish_readiness() :: :ok
  def publish_readiness do
    subset = BeaconChain.subset_from_address(Crypto.node_public_key(0))

    ready_date = DateTime.utc_now()

    message = %AddNodeInfo{
      subset: subset,
      node_info: %NodeInfo{
        public_key: Crypto.node_public_key(),
        timestamp: ready_date,
        ready?: true
      }
    }

    subset
    |> BeaconChain.get_pool(ready_date)
    |> P2P.broadcast_message(message)
    |> Stream.run()
  end
end
