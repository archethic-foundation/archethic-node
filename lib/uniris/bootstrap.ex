defmodule Uniris.Bootstrap do
  @moduledoc """
  Manage Uniris Node Bootstrapping
  """

  alias __MODULE__.NetworkInit
  alias __MODULE__.Sync
  alias __MODULE__.TransactionHandler

  alias Uniris.Crypto

  alias Uniris.Networking

  alias Uniris.P2P
  alias Uniris.P2P.Node
  alias Uniris.P2P.Transport

  alias Uniris.SelfRepair

  require Logger

  use Task

  @genesis_seed Application.compile_env(:uniris, [NetworkInit, :genesis_seed])
  @genesis_pools Application.compile_env(:uniris, [NetworkInit, :genesis_pools])

  @doc """
  Start the bootstrapping as a task
  """
  @spec start_link(list()) :: {:ok, pid()}
  def start_link(args \\ []) do
    ip = Networking.get_node_ip()
    port = Keyword.get(args, :port)
    transport = Keyword.get(args, :transport)
    reward_address = Keyword.get(args, :reward_address)

    last_sync_date = SelfRepair.last_sync_date()
    bootstrapping_seeds = P2P.list_bootstrapping_seeds()

    Task.start_link(__MODULE__, :run, [
      ip,
      port,
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
          Transport.supported(),
          list(Node.t()),
          DateTime.t() | nil,
          Crypto.versioned_hash()
        ) :: :ok
  def run(ip = {_, _, _, _}, port, transport, bootstrapping_seeds, last_sync_date, reward_address)
      when is_number(port) and is_list(bootstrapping_seeds) and is_binary(reward_address) do
    network_patch =
      case P2P.get_node_info(Crypto.first_node_public_key()) do
        {:ok, %Node{network_patch: patch}} ->
          patch

        _ ->
          P2P.get_geo_patch(ip)
      end

    if should_bootstrap?(ip, port, transport, last_sync_date) do
      start_bootstrap(
        ip,
        port,
        transport,
        bootstrapping_seeds,
        last_sync_date,
        network_patch,
        reward_address
      )
    else
      P2P.set_node_globally_available(Crypto.first_node_public_key())
      post_bootstrap(last_sync_date: last_sync_date, sync?: false)
    end
  end

  defp should_bootstrap?(_ip, _port, _, nil), do: true

  defp should_bootstrap?(ip, port, transport, last_sync_date) do
    case P2P.get_node_info(Crypto.first_node_public_key()) do
      {:ok, _} ->
        if Sync.require_update?(ip, port, transport, last_sync_date) do
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
      tx = TransactionHandler.create_node_transaction(ip, port, transport, reward_address)
      Sync.initialize_network(tx)

      post_bootstrap(sync?: false)
      SelfRepair.put_last_sync_date(DateTime.utc_now())
    else
      if Crypto.first_node_public_key() == Crypto.last_node_public_key() do
        Logger.info("Node initialization...")

        first_initialization(
          ip,
          port,
          transport,
          network_patch,
          bootstrapping_seeds,
          reward_address
        )

        post_bootstrap(patch: network_patch, sync?: true)
      else
        if Sync.require_update?(ip, port, transport, last_sync_date) do
          Logger.info("Update node chain...")
          update_node(ip, port, transport, network_patch, bootstrapping_seeds, reward_address)
          post_bootstrap(patch: network_patch, sync?: true, new_sync_date: DateTime.utc_now())
        else
          post_bootstrap(patch: network_patch, sync?: false, last_sync_date: last_sync_date)
        end
      end
    end

    Logger.info("Bootstrapping finished!")
  end

  defp post_bootstrap(opts) do
    last_sync_date = Keyword.get(opts, :last_sync_date, SelfRepair.default_last_sync_date())

    if Keyword.get(opts, :sync?, true) do
      patch = Keyword.fetch!(opts, :patch)

      Logger.info("Synchronization started")
      :ok = SelfRepair.bootstrap_sync(last_sync_date, patch)
      Logger.info("Synchronization finished")

      Sync.publish_end_of_sync()
    end

    SelfRepair.start_scheduler(last_sync_date)

    :persistent_term.put(:uniris_up, :up)
  end

  defp first_initialization(ip, port, transport, patch, bootstrapping_seeds, reward_address) do
    Enum.each(bootstrapping_seeds, &P2P.add_and_connect_node/1)

    closest_nodes = Sync.get_closest_nodes_and_renew_seeds(bootstrapping_seeds, patch)

    tx = TransactionHandler.create_node_transaction(ip, port, transport, reward_address)
    :ok = TransactionHandler.send_transaction(tx, closest_nodes)

    :ok = Sync.load_storage_nonce(closest_nodes)
    :ok = Sync.load_node_list(closest_nodes)
  end

  defp update_node(ip, port, transport, patch, bootstrapping_seeds, reward_address) do
    case Enum.reject(
           bootstrapping_seeds,
           &(&1.first_public_key == Crypto.first_node_public_key())
         ) do
      [] ->
        Logger.warning("Not enough nodes in the network. No node update")

      _ ->
        closest_nodes = Sync.get_closest_nodes_and_renew_seeds(bootstrapping_seeds, patch)

        tx = TransactionHandler.create_node_transaction(ip, port, transport, reward_address)
        :ok = TransactionHandler.send_transaction(tx, closest_nodes)
    end
  end

  @doc """
  Return the address which performed the initial allocation
  """
  @spec genesis_address() :: binary()
  def genesis_address do
    {pub, _} = Crypto.derive_keypair(@genesis_seed, 1)
    Crypto.hash(pub)
  end

  @doc """
  Return the address from the unspent outputs allocation for the genesis transaction
  """
  @spec genesis_unspent_output_address() :: binary()
  def genesis_unspent_output_address do
    {pub, _} = Crypto.derive_keypair(@genesis_seed, 0)
    Crypto.hash(pub)
  end

  @doc """
  Return the amount of token initialized on the network bootstrapping
  """
  @spec genesis_allocation() :: float()
  def genesis_allocation do
    network_pool_amount = 1.46e9

    Enum.reduce(@genesis_pools, network_pool_amount, fn {_, [public_key: _, amount: amount]},
                                                        acc ->
      acc + amount
    end)
  end
end
