defmodule Archethic.Bootstrap do
  @moduledoc """
  Manage Archethic Node Bootstrapping
  """

  alias Archethic.Crypto

  alias Archethic.P2P.GeoPatch

  alias Archethic.Networking

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.NodeConfig

  alias Archethic.Replication

  alias Archethic.SelfRepair

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias __MODULE__.NetworkInit
  alias __MODULE__.Sync
  alias __MODULE__.TransactionHandler

  require Logger

  use Task, restart: :transient

  @doc """
  Start the bootstrapping as a task
  """
  @spec start_link(list()) :: {:ok, pid()}
  def start_link(args \\ []), do: Task.start_link(__MODULE__, :run, [args])

  @doc """
  Start the bootstrap workflow.

  The first node in the network will initialized the storage nonce, the first node shared secrets, genesis wallets
  as well as his own node transaction. Those transactions will be self validated and self replicated.

  Other nodes will initialize or update (if ip, port change or disconnected from long time) their own node transaction chain.

  Once sent, they will start the self repair synchronization using the Beacon chain to retrieve the missed transactions.

  Once done, the synchronization/self repair mechanism is terminated, the node will publish to the Beacon chain its readiness.
  Hence others nodes will be able to communicate with and support new transactions.
  """
  @spec run(args :: Keyword.t()) :: :ok
  def run(args) do
    Logger.info("Node bootstrapping...")

    node_config =
      %NodeConfig{
        first_public_key: first_public_key,
        geo_patch: geo_patch,
        reward_address: reward_address
      } = get_node_config(args)

    Logger.info("Rewards will be transfered to #{Base.encode16(reward_address)}")

    network_patch =
      case P2P.get_node_info(first_public_key) do
        {:ok, %Node{network_patch: patch}} -> patch
        _ -> geo_patch
      end

    bootstrapping_seeds = P2P.list_bootstrapping_seeds()

    closest_bootstrapping_nodes =
      get_closest_nodes(bootstrapping_seeds, network_patch, first_public_key)

    last_sync_date = SelfRepair.last_sync_date()

    if should_bootstrap?(node_config, last_sync_date) do
      start_bootstrap(node_config, closest_bootstrapping_nodes)
    else
      Logger.debug("Node chain doesn't need to be updated")
    end

    post_bootstrap(closest_bootstrapping_nodes)

    Logger.info("Bootstrapping finished!")
  end

  defp get_node_config(args) do
    node_public_key = Crypto.first_node_public_key()

    ip =
      case Networking.get_node_ip() do
        {:ok, ip} -> ip
        {:error, reason} -> raise "Cannot retrieve public ip: #{inspect(reason)}"
      end

    port = Keyword.get(args, :port)
    http_port = Keyword.get(args, :http_port)
    transport = Keyword.get(args, :transport)

    reward_address =
      case Keyword.get(args, :reward_address) do
        nil -> Crypto.derive_address(node_public_key)
        "" -> Crypto.derive_address(node_public_key)
        address -> address
      end

    origin_public_key = Crypto.origin_node_public_key()
    origin_public_certificate = Crypto.get_key_certificate(origin_public_key)
    mining_public_key = Crypto.mining_node_public_key()
    geo_patch = GeoPatch.from_ip(ip)

    %NodeConfig{
      first_public_key: node_public_key,
      ip: ip,
      port: port,
      http_port: http_port,
      transport: transport,
      reward_address: reward_address,
      origin_public_key: origin_public_key,
      origin_certificate: origin_public_certificate,
      mining_public_key: mining_public_key,
      geo_patch: geo_patch
    }
  end

  defp get_closest_nodes(bootstrapping_seeds, network_patch, first_public_key) do
    case bootstrapping_seeds do
      [%Node{first_public_key: ^first_public_key}] ->
        bootstrapping_seeds

      nodes ->
        P2P.connect_nodes(nodes)

        case Sync.get_closest_nodes_and_renew_seeds(nodes, network_patch) do
          {:ok, closest_nodes} -> closest_nodes
          _ -> []
        end
    end
  end

  defp should_bootstrap?(_, nil), do: true

  defp should_bootstrap?(
         node_config = %NodeConfig{first_public_key: first_public_key},
         last_sync_date
       ) do
    case P2P.get_node_info(first_public_key) do
      {:ok, _} -> Sync.require_update?(node_config, last_sync_date)
      _ -> true
    end
  end

  defp start_bootstrap(
         node_config = %NodeConfig{first_public_key: first_public_key},
         closest_bootstrapping_nodes
       ) do
    if Sync.should_initialize_network?(closest_bootstrapping_nodes, first_public_key) do
      Logger.info("This node should initialize the network!!")
      Logger.debug("Create first node transaction")

      node_config |> TransactionHandler.create_node_transaction() |> Sync.initialize_network()

      SelfRepair.put_last_sync_date(DateTime.utc_now())
    else
      node_genesis_address = first_public_key |> Crypto.derive_address()

      # In case node had lose it's DB, we ask the network if the node chain already exists
      {:ok, length} =
        TransactionChain.fetch_size(node_genesis_address, closest_bootstrapping_nodes)

      node_config =
        if length == 0 do
          Logger.debug("Node doesn't exists. It will be bootstrap and create a new chain")
          node_config
        else
          Logger.debug("Node chain need to be updated")
          Crypto.set_node_key_index(length)

          last_reward_address =
            get_last_reward_address(node_genesis_address, closest_bootstrapping_nodes)

          %NodeConfig{node_config | reward_address: last_reward_address}
        end

      {:ok, validated_tx} =
        node_config
        |> TransactionHandler.create_node_transaction()
        |> TransactionHandler.send_transaction(closest_bootstrapping_nodes)

      Sync.load_storage_nonce(closest_bootstrapping_nodes)

      Replication.sync_transaction_chain(
        validated_tx,
        node_genesis_address,
        closest_bootstrapping_nodes
      )
    end
  end

  defp get_last_reward_address(genesis_address, nodes) do
    {:ok, last_address} = TransactionChain.fetch_last_address(genesis_address, nodes)

    {:ok, %Transaction{data: %TransactionData{content: content}}} =
      TransactionChain.fetch_transaction(last_address, nodes)

    {:ok, %NodeConfig{reward_address: last_reward_address}} =
      Node.decode_transaction_content(content)

    last_reward_address
  end

  defp post_bootstrap(closest_bootstrapping_nodes) do
    last_sync_date = SelfRepair.last_sync_date()

    if SelfRepair.missed_sync?(last_sync_date) and closest_bootstrapping_nodes != [] do
      Logger.info("Synchronization started")
      # Always load the current node list to have the current view for downloading transaction
      {:ok, current_nodes} = Sync.connect_current_node(closest_bootstrapping_nodes)
      :ok = SelfRepair.bootstrap_sync(current_nodes)
      Logger.info("Synchronization finished")
    end

    # Connect nodes after all synchronization are finished
    # so we have the latest connection infos available at this time
    Logger.info("Try connection on all nodes")
    P2P.list_nodes() |> P2P.connect_nodes()

    Archethic.Bootstrap.NetworkConstraints.persist_genesis_address()

    if P2P.authorized_and_available_node?() do
      Logger.info("Current summary synchronization started")
      count = SelfRepair.synchronize_current_summary()
      Logger.info("Current summary synchronization finished: #{count} synchronized")
    end

    Sync.publish_end_of_sync()
    SelfRepair.start_scheduler()

    :persistent_term.put(:archethic_up, :up)
    Archethic.PubSub.notify_node_status(:node_up)
  end

  @doc """
  Return the address which performed the initial allocation
  """
  @spec genesis_address() :: binary()
  def genesis_address do
    get_genesis_seed()
    |> Crypto.derive_keypair(1)
    |> elem(0)
    |> Crypto.derive_address()
  end

  @doc """
  Return the address from the unspent outputs allocation for the genesis transaction
  """
  @spec genesis_unspent_output_address() :: binary()
  def genesis_unspent_output_address do
    get_genesis_seed()
    |> Crypto.derive_keypair(0)
    |> elem(0)
    |> Crypto.derive_address()
  end

  @doc """
  Return the amount of token initialized on the network bootstrapping
  """
  @spec genesis_allocation() :: float()
  def genesis_allocation do
    reward_amount = 1.46e9

    genesis_pools =
      :archethic
      |> Application.get_env(NetworkInit)
      |> Keyword.fetch!(:genesis_pools)

    Enum.reduce(genesis_pools, reward_amount, &(&1.amount + &2))
  end

  defp get_genesis_seed do
    :archethic
    |> Application.get_env(NetworkInit)
    |> Keyword.fetch!(:genesis_seed)
  end
end
