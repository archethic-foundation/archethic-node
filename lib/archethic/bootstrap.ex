defmodule ArchEthic.Bootstrap do
  @moduledoc """
  Manage ArchEthic Node Bootstrapping
  """

  alias __MODULE__.NetworkInit
  alias __MODULE__.Sync
  alias __MODULE__.TransactionHandler

  alias ArchEthic.Crypto

  alias ArchEthic.Networking

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.SelfRepair

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
    IO.inspect(http_port,
      label: "<---------- [http_port] ---------->",
      limit: :infinity,
      printable_limit: :infinity
    )

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
      P2P.set_node_globally_available(Crypto.first_node_public_key())
      post_bootstrap(sync?: false)
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

    Logger.info("Bootstrapping finished!")
  end

  defp post_bootstrap(opts) do
    if Keyword.get(opts, :sync?, true) do
      patch = Keyword.fetch!(opts, :patch)

      Logger.info("Synchronization started")
      :ok = SelfRepair.bootstrap_sync(SelfRepair.last_sync_date(), patch)
      Logger.info("Synchronization finished")
    end

    Sync.publish_end_of_sync()
    SelfRepair.start_scheduler()

    :persistent_term.put(:archethic_up, :up)
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
