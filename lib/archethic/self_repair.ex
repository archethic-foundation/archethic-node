defmodule Archethic.SelfRepair do
  @moduledoc """
  Synchronization for all the Archethic nodes relies on the self-repair mechanism started during
  the bootstrapping phase and stores last synchronization date after each cycle.
  """

  alias __MODULE__.{Notifier, NotifierSupervisor, RepairRegistry, RepairWorker}
  alias __MODULE__.{Scheduler, Sync}

  alias Archethic.{BeaconChain, Crypto, Utils, Contracts, TransactionChain, Election}
  alias Archethic.{P2P, P2P.Node, SharedSecrets, OracleChain, Reward, Replication}

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  require Logger

  @max_retry_count 10

  @doc """
  Start the self repair synchronization scheduler
  """
  @spec start_scheduler() :: :ok
  defdelegate start_scheduler, to: Scheduler

  @doc """
  Start the bootstrap's synchronization process using the last synchronization date
  """
  @spec bootstrap_sync(last_sync_date :: DateTime.t()) :: :ok
  def bootstrap_sync(date = %DateTime{}) do
    # Loading transactions can take a lot of time to be achieve and can overpass an epoch.
    # So to avoid missing a beacon summary epoch, we save the starting date and update the last sync date with it
    # at the end of loading (in case there is a crash during self repair).

    # Summary time after the the last synchronization date
    summary_time = BeaconChain.next_summary_date(date)

    # Before the first summary date, synchronization is useless
    # as no data have been aggregated
    if DateTime.diff(DateTime.utc_now(), summary_time) >= 0 do
      loaded_missed_transactions? =
        :ok ==
          0..@max_retry_count
          |> Enum.reduce_while(:error, fn _, _ ->
            try do
              :ok = Sync.load_missed_transactions(date)
              {:halt, :ok}
            catch
              _, _ -> {:cont, :error}
            end
          end)

      if loaded_missed_transactions? do
        Logger.info("Bootstrap Sync succeded in loading missed transactions !")

        # At the end of self repair, if a new beacon summary as been created
        # we run bootstrap_sync again until the last beacon summary is loaded
        last_sync_date = last_sync_date()

        case DateTime.utc_now()
             |> BeaconChain.previous_summary_time()
             |> DateTime.compare(last_sync_date) do
          :gt ->
            bootstrap_sync(last_sync_date)

          _ ->
            :ok
        end
      else
        Logger.error(
          "Bootstrap Sync failed to load missed transactions after max retry of #{@max_retry_count} !"
        )

        :error
      end
    else
      Logger.info("Synchronization skipped (before first summary date)")
    end
  end

  @doc """
  Return the last synchronization date from the previous cycle of self repair
  """
  @spec last_sync_date() :: DateTime.t() | nil
  defdelegate last_sync_date, to: Sync

  @doc """
  Set the next last synchronization date
  """
  @spec put_last_sync_date(DateTime.t()) :: :ok
  defdelegate put_last_sync_date(datetime), to: Sync, as: :store_last_sync_date

  @doc """
  Return the previous scheduler time from a given date
  """
  @spec get_previous_scheduler_repair_time(DateTime.t()) :: DateTime.t()
  def get_previous_scheduler_repair_time(date_from = %DateTime{}) do
    Scheduler.get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_date!(DateTime.to_naive(date_from))
    |> DateTime.from_naive!("Etc/UTC")
  end

  @doc """
  Start a new notifier process if there is new unavailable nodes after the self repair
  """
  @spec start_notifier(list(Node.t()), list(Node.t()), DateTime.t()) :: :ok
  def start_notifier(prev_available_nodes, new_available_nodes, availability_update) do
    diff_node =
      prev_available_nodes
      |> Enum.reject(
        &(Utils.key_in_node_list?(new_available_nodes, &1.first_public_key) or
            &1.first_public_key == Crypto.first_node_public_key())
      )

    case diff_node do
      [] ->
        :ok

      nodes ->
        unavailable_nodes = Enum.map(nodes, & &1.first_public_key)

        DynamicSupervisor.start_child(
          NotifierSupervisor,
          {Notifier,
           unavailable_nodes: unavailable_nodes,
           prev_available_nodes: prev_available_nodes,
           new_available_nodes: new_available_nodes,
           availability_update: availability_update}
        )

        :ok
    end
  end

  @doc """
  Return pid of a running RepairWorker for the first_address, or false
  """
  @spec repair_in_progress?(first_address :: binary()) :: false | pid()
  def repair_in_progress?(first_address) do
    case Registry.lookup(RepairRegistry, first_address) do
      [{pid, _}] ->
        pid

      _ ->
        false
    end
  end

  @doc """
  Start a new RepairWorker for the first_address
  """
  @spec start_worker(list()) :: DynamicSupervisor.on_start_child()
  def start_worker(args) do
    DynamicSupervisor.start_child(NotifierSupervisor, {RepairWorker, args})
  end

  @doc """
  Add a new address in the address list of the RepairWorker
  """
  @spec add_repair_addresses(
          pid(),
          Crypto.prepended_hash() | nil,
          list(Crypto.prepended_hash())
        ) :: :ok
  def add_repair_addresses(pid, storage_address, io_addresses) do
    GenServer.cast(pid, {:add_address, storage_address, io_addresses})
  end

  def config_change(changed_conf) do
    changed_conf
    |> Keyword.get(Scheduler)
    |> Scheduler.config_change()
  end

  @doc """
  Request missing transaction addresses from last local address until last chain address
  and add them in the DB
  """
  def update_last_address(address, authorized_nodes) do
    # As the node is storage node of this chain, it needs to know all the addresses of the chain until the last
    # So we get the local last address and verify if it's the same as the last address of the chain
    # by requesting the nodes which already know the last address

    {last_local_address, _timestamp} = TransactionChain.get_last_address(address)
    storage_nodes = Election.storage_nodes(last_local_address, authorized_nodes)

    case TransactionChain.fetch_next_chain_addresses_remotely(last_local_address, storage_nodes) do
      {:ok, []} ->
        :ok

      {:ok, addresses} ->
        genesis_address = TransactionChain.get_genesis_address(address)

        addresses
        |> Enum.sort_by(fn {_address, timestamp} -> timestamp end)
        |> Enum.each(fn {address, timestamp} ->
          TransactionChain.register_last_address(genesis_address, address, timestamp)
        end)

        # Stop potential previous smart contract
        Contracts.stop_contract(address)

      _ ->
        :ok
    end
  end

  def resync(genesis_address, storage_address) do
    case repair_in_progress?(genesis_address) do
      false ->
        start_worker(
          first_address: genesis_address,
          storage_address: storage_address,
          io_addresses: []
        )

      pid ->
        add_repair_addresses(pid, storage_address, [])
    end

    :ok
  end

  @spec resync_p2p() :: :ok
  def resync_p2p() do
    spawn(fn ->
      # avoid running it multiple times concurrently
      unless :persistent_term.get(:resync_p2p_running, false) do
        try do
          :persistent_term.put(:resync_p2p_running, true)

          nearest_nodes =
            P2P.authorized_and_available_nodes()
            |> Enum.filter(&Node.locally_available?/1)
            |> P2P.nearest_nodes()
            |> Enum.take(3)

          Archethic.Bootstrap.Sync.load_node_list(nearest_nodes)
        after
          :persistent_term.put(:resync_p2p_running, false)
        end
      end
    end)

    :ok
  end

  @spec resync_all_network_chains() :: :ok
  def resync_all_network_chains() do
    spawn(fn ->
      Task.Supervisor.async_stream_nolink(
        Archethic.TaskSupervisor,
        [:node_shared_secrets, :oracle, :origin],
        &resync_network_chain(&1, P2P.authorized_and_available_nodes()),
        ordered: false,
        on_timeout: :kill_task,
        timeout: 5000
      )
      |> Stream.run()
    end)

    :ok
  end

  @spec resync_network_chain(atom(), list(Node.t()) | []) :: :ok
  def resync_network_chain(_, []),
    do: Logger.notice("Enforce Resync of Network Txs: No-Nodes")

  def resync_network_chain(type, nodes) do
    addresses =
      case type do
        :node_shared_secrets ->
          [SharedSecrets.genesis_address(:node_shared_secrets)]

        :oracle ->
          [OracleChain.get_current_genesis_address()]

        :reward ->
          [Reward.genesis_address()]

        :origin ->
          SharedSecrets.genesis_address(:origin)
      end

    Task.Supervisor.async_stream_nolink(
      Archethic.TaskSupervisor,
      addresses,
      &do_resync_network_chain(&1, type, nodes),
      ordered: false,
      on_timeout: :kill_task,
      timeout: 5000
    )
    |> Stream.run()
  end

  # FIXME: why is it not using the repair worker?
  def do_resync_network_chain(genesis_address, type, nodes) do
    with {:ok, rem_last_addr} <- TransactionChain.resolve_last_address(genesis_address),
         {local_last_addr, _} <- TransactionChain.get_last_address(genesis_address),
         false <- rem_last_addr == local_last_addr,
         {:ok, tx} <- TransactionChain.fetch_transaction_remotely(rem_last_addr, nodes),
         :ok <- Replication.validate_and_store_transaction_chain(tx) do
      Logger.info("Enforced Resync: Success", transaction_type: type)
      :ok
    else
      nil ->
        Logger.warning("Node is out of sync, wait for self repair to complete succesfully.")

      true ->
        Logger.info("Enforced Resync: No new transaction to sync", transaction_type: type)
        :ok

      e ->
        Logger.debug("Enforced Resync: Error #{inspect(e)}", transaction_type: type)
    end
  end
end
