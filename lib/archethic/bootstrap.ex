defmodule Archethic.Bootstrap do
  @moduledoc """
  Manage Archethic Node Bootstrapping
  """

  alias Archethic.Crypto

  alias Archethic.Networking

  alias Archethic.P2P
  alias Archethic.P2P.Node

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
  def start_link(args \\ []) do
    {:ok, ip} = Networking.get_node_ip()
    port = Keyword.get(args, :port)
    http_port = Keyword.get(args, :http_port)
    transport = Keyword.get(args, :transport)

    reward_address =
      case Keyword.get(args, :reward_address) do
        nil ->
          Crypto.derive_address(Crypto.first_node_public_key())

        "" ->
          Crypto.derive_address(Crypto.first_node_public_key())

        address ->
          address
      end

    last_sync_date = SelfRepair.last_sync_date()
    bootstrapping_seeds = P2P.list_bootstrapping_seeds()

    Logger.info("Node bootstrapping...")
    Logger.info("Rewards will be transfered to #{Base.encode16(reward_address)}")

    Task.start_link(__MODULE__, :run, [
      ip,
      port,
      http_port,
      transport,
      bootstrapping_seeds,
      last_sync_date,
      reward_address
    ])
  end

  @doc """
  Start the bootstrap workflow.

  The first node in the network will initialized the storage nonce, the first node shared secrets, genesis wallets
  as well as his own node transaction. Those transactions will be self validated and self replicated.

  Other nodes will initialize or update (if ip, port change or disconnected from long time) their own node transaction chain.

  Once sent, they will start the self repair synchronization using the Beacon chain to retrieve the missed transactions.

  Once done, the synchronization/self repair mechanism is terminated, the node will publish to the Beacon chain its readiness.
  Hence others nodes will be able to communicate with and support new transactions.
  """
  @spec run(
          :inet.ip_address(),
          :inet.port_number(),
          :inet.port_number(),
          P2P.supported_transport(),
          list(Node.t()),
          DateTime.t() | nil,
          Crypto.versioned_hash()
        ) :: :ok
  def run(
        ip = {_, _, _, _},
        port,
        http_port,
        transport,
        bootstrapping_seeds,
        last_sync_date,
        reward_address
      )
      when is_number(port) and is_list(bootstrapping_seeds) and is_binary(reward_address) do
    network_patch = get_network_patch(ip)

    closest_bootstrapping_nodes = get_closest_nodes(bootstrapping_seeds, network_patch)

    if should_bootstrap?(ip, port, http_port, transport, last_sync_date) do
      start_bootstrap(
        ip,
        port,
        http_port,
        transport,
        closest_bootstrapping_nodes,
        reward_address
      )
    end

    post_bootstrap(closest_bootstrapping_nodes)

    Logger.info("Bootstrapping finished!")
  end

  defp get_network_patch(ip) do
    case P2P.get_node_info(Crypto.first_node_public_key()) do
      {:ok, %Node{network_patch: patch}} ->
        patch

      _ ->
        P2P.get_geo_patch(ip)
    end
  end

  defp get_closest_nodes(bootstrapping_seeds, network_patch) do
    node_first_public_key = Crypto.first_node_public_key()

    case bootstrapping_seeds do
      [%Node{first_public_key: ^node_first_public_key}] ->
        bootstrapping_seeds

      nodes ->
        P2P.connect_nodes(nodes)

        case Sync.get_closest_nodes_and_renew_seeds(nodes, network_patch) do
          {:ok, closest_nodes} when closest_nodes != [] ->
            closest_nodes

          _ ->
            []
        end
    end
  end

  defp should_bootstrap?(_ip, _port, _http_port, _, nil), do: true

  defp should_bootstrap?(ip, port, http_port, transport, last_sync_date) do
    case P2P.get_node_info(Crypto.first_node_public_key()) do
      {:ok, _} ->
        if Sync.require_update?(ip, port, http_port, transport, last_sync_date) do
          Logger.debug("Node chain need to updated")
          true
        else
          Logger.debug("Node chain doesn't need to be updated")
          false
        end

      _ ->
        Logger.debug("Node doesn't exists. It will be bootstrap and create a new chain")
        true
    end
  end

  defp start_bootstrap(
         ip,
         port,
         http_port,
         transport,
         closest_bootstrapping_nodes,
         configured_reward_address
       ) do
    Logger.info("Bootstrapping starting")

    cond do
      Sync.should_initialize_network?(closest_bootstrapping_nodes) ->
        Logger.info("This node should initialize the network!!")
        Logger.debug("Create first node transaction")

        tx =
          TransactionHandler.create_node_transaction(
            ip,
            port,
            http_port,
            transport,
            configured_reward_address
          )

        Sync.initialize_network(tx)

        SelfRepair.put_last_sync_date(DateTime.utc_now())

      Crypto.first_node_public_key() == Crypto.previous_node_public_key() ->
        Logger.info("Node initialization...")

        first_initialization(
          ip,
          port,
          http_port,
          transport,
          closest_bootstrapping_nodes,
          configured_reward_address
        )

      true ->
        Logger.info("Update node chain...")

        {:ok, %Transaction{data: %TransactionData{content: content}}} =
          TransactionChain.get_last_transaction(
            Crypto.derive_address(Crypto.first_node_public_key())
          )

        {:ok, _ip, _p2p_port, _http_port, _transport, last_reward_address, _origin_public_key,
         _key_certificate, _mining_public_key} = Node.decode_transaction_content(content)

        update_node(
          ip,
          port,
          http_port,
          transport,
          closest_bootstrapping_nodes,
          last_reward_address
        )
    end
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

  defp first_initialization(
         ip,
         port,
         http_port,
         transport,
         closest_bootstrapping_nodes,
         configured_reward_address
       ) do
    # In case node had lose it's DB, we ask the network if the node chain already exists
    {:ok, length} =
      Crypto.first_node_public_key()
      |> Crypto.derive_address()
      |> TransactionChain.fetch_size(closest_bootstrapping_nodes)

    Crypto.set_node_key_index(length)

    node_genesis_address = Crypto.first_node_public_key() |> Crypto.derive_address()

    reward_address =
      if length > 0 do
        {:ok, last_address} =
          TransactionChain.fetch_last_address(node_genesis_address, closest_bootstrapping_nodes)

        {:ok, %Transaction{data: %TransactionData{content: content}}} =
          TransactionChain.fetch_transaction(last_address, closest_bootstrapping_nodes)

        {:ok, _ip, _p2p_port, _http_port, _transport, last_reward_address, _origin_public_key,
         _key_certificate, _mining_public_key} = Node.decode_transaction_content(content)

        last_reward_address
      else
        configured_reward_address
      end

    tx =
      TransactionHandler.create_node_transaction(ip, port, http_port, transport, reward_address)

    {:ok, validated_tx} = TransactionHandler.send_transaction(tx, closest_bootstrapping_nodes)

    :ok = Sync.load_storage_nonce(closest_bootstrapping_nodes)

    Replication.sync_transaction_chain(
      validated_tx,
      node_genesis_address,
      closest_bootstrapping_nodes
    )
  end

  defp update_node(_ip, _port, _http_port, _transport, [], _reward_address) do
    Logger.warning("Not enough nodes in the network. No node update")
  end

  defp update_node(ip, port, http_port, transport, closest_bootstrapping_nodes, reward_address) do
    tx =
      TransactionHandler.create_node_transaction(
        ip,
        port,
        http_port,
        transport,
        reward_address
      )

    {:ok, validated_tx} = TransactionHandler.send_transaction(tx, closest_bootstrapping_nodes)

    node_genesis_address = Crypto.first_node_public_key() |> Crypto.derive_address()

    Replication.sync_transaction_chain(
      validated_tx,
      node_genesis_address,
      closest_bootstrapping_nodes
    )
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
