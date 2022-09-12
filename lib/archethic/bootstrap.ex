defmodule Archethic.Bootstrap do
  @moduledoc """
  Manage Archethic Node Bootstrapping
  """

  alias Archethic.Bootstrap.{
    NetworkInit,
    Sync,
    TransactionHandler
  }

  alias Archethic.{
    Crypto,
    Networking,
    P2P,
    P2P.Node,
    P2P.Listener,
    SelfRepair,
    TransactionChain,
    Replication
  }

  require Logger

  use Task

  @doc """
  Start the bootstrapping as a task
  """
  @spec start_link(list()) :: {:ok, pid()}
  def start_link(args \\ []) do
    ip = Networking.get_node_ip()
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
    network_patch =
      case P2P.get_node_info(Crypto.first_node_public_key()) do
        {:ok, %Node{network_patch: patch}} ->
          patch

        _ ->
          P2P.get_geo_patch(ip)
      end

    if should_bootstrap?(ip, port, http_port, transport, last_sync_date) do
      start_bootstrap(
        ip,
        port,
        http_port,
        transport,
        bootstrapping_seeds,
        last_sync_date,
        network_patch,
        reward_address
      )
    else
      post_bootstrap(sync?: false)
    end

    Logger.info("Bootstrapping finished!")
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
         bootstrapping_seeds,
         last_sync_date,
         network_patch,
         reward_address
       ) do
    Logger.info("Bootstrapping starting")

    if Sync.should_initialize_network?(bootstrapping_seeds) do
      Logger.info("This node should initialize the network!!")
      Logger.debug("Create first node transaction")

      tx =
        TransactionHandler.create_node_transaction(ip, port, http_port, transport, reward_address)

      Sync.initialize_network(tx)

      post_bootstrap(sync?: false)
      SelfRepair.put_last_sync_date(DateTime.utc_now())
    else
      if Crypto.first_node_public_key() == Crypto.last_node_public_key() do
        Logger.info("Node initialization...")

        first_initialization(
          ip,
          port,
          http_port,
          transport,
          network_patch,
          bootstrapping_seeds,
          reward_address
        )

        post_bootstrap(patch: network_patch, sync?: true)
      else
        if Sync.require_update?(ip, port, http_port, transport, last_sync_date) do
          Logger.info("Update node chain...")

          update_node(
            ip,
            port,
            http_port,
            transport,
            network_patch,
            bootstrapping_seeds,
            reward_address
          )

          post_bootstrap(patch: network_patch, sync?: true)
        else
          post_bootstrap(patch: network_patch, sync?: false)
        end
      end
    end
  end

  defp post_bootstrap(opts) do
    if Keyword.get(opts, :sync?, true) do
      patch = Keyword.fetch!(opts, :patch)

      Logger.info("Synchronization started")
      :ok = SelfRepair.bootstrap_sync(SelfRepair.last_sync_date(), patch)
      Logger.info("Synchronization finished")
    end

    Archethic.Bootstrap.NetworkConstraints.persist_genesis_address()
    resync_network_chain()

    Sync.publish_end_of_sync()
    SelfRepair.start_scheduler()

    :persistent_term.put(:archethic_up, :up)
    Archethic.PubSub.notify_node_up()
    Listener.listen()
  end

  def resync_network_chain() do
    Logger.info("Enforced Resync: Started!")

    if P2P.authorized_node?() && P2P.available_node?() do
      # evict this node
      nodes =
        Enum.reject(
          P2P.authorized_and_available_nodes(),
          &(&1.first_public_key == Crypto.first_node_public_key())
        )

      do_resync_network_chain([:oracle, :node_shared_secrets], nodes)
    end
  end

  @spec do_resync_network_chain(list(atom), list(P2P.Node.t()) | []) :: :ok
  def do_resync_network_chain(_type_list, _nodes = []),
    do: Logger.info("Enforce Reync of Network Txs: failure, No-Nodes")

  # by type: Get gen addr, get last address (remotely  & locally)
  # compare, if dont match, fetch last tx remotely
  def do_resync_network_chain(type_list, nodes) when is_list(nodes) do
    Task.Supervisor.async_stream_nolink(Archethic.TaskSupervisor, type_list, fn type ->
      with addr when is_binary(addr) <- get_genesis_addr(type),
           {:ok, rem_last_addr} <- TransactionChain.resolve_last_address(addr),
           {local_last_addr, _} <- TransactionChain.get_last_address(addr),
           false <- rem_last_addr == local_last_addr,
           {:ok, tx} <- TransactionChain.fetch_transaction_remotely(rem_last_addr, nodes),
           :ok <- Replication.validate_and_store_transaction_chain(tx) do
        Logger.info("Enforced Resync: Success", transaction_type: type)
        :ok
      else
        true ->
          Logger.info("Enforced Resync: No new transaction to sync", transaction_type: type)
          :ok

        e when e in [nil, []] ->
          Logger.debug("Enforced Resync: Transaction not available", transaction_type: type)
          :ok

        e ->
          Logger.debug("Enforced Resync: Unexpected Error", transaction_type: type)
          Logger.debug(e)
      end
    end)
    |> Stream.run()
  end

  @spec get_genesis_addr(:node_shared_secrets | :oracle) :: binary() | nil
  defp get_genesis_addr(:oracle) do
    Archethic.OracleChain.get_gen_addr().current |> elem(0)
  end

  defp get_genesis_addr(:node_shared_secrets) do
    Archethic.SharedSecrets.get_gen_addr(:node_shared_secrets)
  end

  defp first_initialization(
         ip,
         port,
         http_port,
         transport,
         patch,
         bootstrapping_seeds,
         reward_address
       ) do
    Enum.each(bootstrapping_seeds, &P2P.add_and_connect_node/1)

    {:ok, closest_nodes} = Sync.get_closest_nodes_and_renew_seeds(bootstrapping_seeds, patch)

    tx =
      TransactionHandler.create_node_transaction(ip, port, http_port, transport, reward_address)

    :ok = TransactionHandler.send_transaction(tx, closest_nodes)

    :ok = Sync.load_storage_nonce(closest_nodes)
    :ok = Sync.load_node_list(closest_nodes)
  end

  defp update_node(ip, port, http_port, transport, patch, bootstrapping_seeds, reward_address) do
    case Enum.reject(
           bootstrapping_seeds,
           &(&1.first_public_key == Crypto.first_node_public_key())
         ) do
      [] ->
        Logger.warning("Not enough nodes in the network. No node update")

      _ ->
        {:ok, closest_nodes} = Sync.get_closest_nodes_and_renew_seeds(bootstrapping_seeds, patch)

        closest_nodes =
          closest_nodes
          |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))

        tx =
          TransactionHandler.create_node_transaction(
            ip,
            port,
            http_port,
            transport,
            reward_address
          )

        :ok = TransactionHandler.send_transaction(tx, closest_nodes)
    end
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
    network_pool_amount = 1.46e9

    genesis_pools =
      :archethic
      |> Application.get_env(NetworkInit)
      |> Keyword.fetch!(:genesis_pools)

    Enum.reduce(genesis_pools, network_pool_amount, &(&1.amount + &2))
  end

  defp get_genesis_seed do
    :archethic
    |> Application.get_env(NetworkInit)
    |> Keyword.fetch!(:genesis_seed)
  end
end
