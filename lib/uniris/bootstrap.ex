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

    last_sync_date = SelfRepair.last_sync_date()
    bootstrapping_seeds = P2P.list_bootstrapping_seeds()

    Task.start_link(__MODULE__, :run, [ip, port, transport, bootstrapping_seeds, last_sync_date])
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
          DateTime.t() | nil
        ) :: :ok
  def run(ip = {_, _, _, _}, port, transport, bootstrapping_seeds, last_sync_date)
      when is_number(port) and is_list(bootstrapping_seeds) do
    if should_bootstrap?(ip, port, transport, last_sync_date) do
      start_bootstrap(ip, port, transport, bootstrapping_seeds, last_sync_date)
    else
      P2P.set_node_globally_available(Crypto.node_public_key(0))
    end
  end

  defp should_bootstrap?(_ip, _port, _, nil), do: true

  defp should_bootstrap?(ip, port, transport, last_sync_date) do
    case P2P.get_node_info(Crypto.node_public_key(0)) do
      {:ok, _} ->
        Sync.require_update?(ip, port, transport, last_sync_date)

      _ ->
        true
    end
  end

  defp start_bootstrap(ip, port, transport, bootstrapping_seeds, last_sync_date) do
    Logger.info("Bootstrapping starting")

    patch = P2P.get_geo_patch(ip)

    if Sync.should_initialize_network?(bootstrapping_seeds) do
      Logger.info("Create first node transaction")
      tx = TransactionHandler.create_node_transaction(ip, port, transport)
      Sync.initialize_network(tx)

      :ok = SelfRepair.put_last_sync_date(DateTime.utc_now())
      :ok = SelfRepair.start_scheduler(DateTime.utc_now())
    else
      if Crypto.number_of_node_keys() == 0 do
        Logger.info("Node initialization...")
        first_initialization(ip, port, transport, patch, bootstrapping_seeds)
      else
        if Sync.require_update?(ip, port, transport, last_sync_date) do
          Logger.info("Update node chain...")
          update_node(ip, port, transport, patch, bootstrapping_seeds)
        else
          :ok
        end
      end
    end

    Logger.info("Bootstrapping finished!")
  end

  defp first_initialization(ip, port, transport, patch, bootstrapping_seeds) do
    closest_node =
      bootstrapping_seeds
      |> Sync.get_closest_nodes_and_renew_seeds(patch)
      |> List.first()

    tx = TransactionHandler.create_node_transaction(ip, port, transport)

    ack_task = Task.async(fn -> TransactionHandler.await_validation(tx.address, closest_node) end)

    :ok = TransactionHandler.send_transaction(tx, closest_node)
    Logger.info("Node transaction sent")

    Logger.info("Waiting transaction replication")
    :ok = Task.await(ack_task, :infinity)

    :ok = Sync.load_storage_nonce(closest_node)
    :ok = Sync.load_node_list(closest_node)

    Logger.info("Synchronization started")
    :ok = SelfRepair.sync(patch)
    Logger.info("Synchronization finished")

    :ok = SelfRepair.put_last_sync_date(DateTime.utc_now())
    :ok = SelfRepair.start_scheduler(DateTime.utc_now())

    Sync.publish_end_of_sync()
  end

  defp update_node(ip, port, transport, patch, bootstrapping_seeds) do
    case Enum.reject(bootstrapping_seeds, &(&1.first_public_key == Crypto.node_public_key(0))) do
      [] ->
        Logger.warn("Not enough nodes in the network. No node update")

      _ ->
        closest_node =
          bootstrapping_seeds
          |> Sync.get_closest_nodes_and_renew_seeds(patch)
          |> List.first()

        tx = TransactionHandler.create_node_transaction(ip, port, transport)

        ack_task =
          Task.async(fn -> TransactionHandler.await_validation(tx.address, closest_node) end)

        :ok = TransactionHandler.send_transaction(tx, closest_node)
        Logger.info("Node transaction sent")

        Logger.info("Waiting transaction replication")
        :ok = Task.await(ack_task, :infinity)

        Logger.info("Synchronization started")
        :ok = SelfRepair.sync(patch)
        Logger.info("Synchronization finished")

        :ok = SelfRepair.put_last_sync_date(DateTime.utc_now())
        :ok = SelfRepair.start_scheduler(DateTime.utc_now())

        Sync.publish_end_of_sync()
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
