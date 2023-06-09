defmodule Archethic.SelfRepair do
  @moduledoc """
  Synchronization for all the Archethic nodes relies on the self-repair mechanism started during
  the bootstrapping phase and stores last synchronization date after each cycle.
  """
  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.Contracts

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Node

  alias Archethic.Replication

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  alias Archethic.Utils

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias __MODULE__.Notifier
  alias __MODULE__.NotifierSupervisor
  alias __MODULE__.Scheduler
  alias __MODULE__.Sync
  alias __MODULE__.RepairWorker

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
              error, message ->
                Logger.error("Error during self repair #{error} #{message}")
                {:cont, :error}
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
  Return true if there is a self repair date missed since the last
  summary synchronized
  """
  @spec missed_sync?(DateTime.t() | nil) :: boolean()
  def missed_sync?(nil), do: true

  def missed_sync?(last_sync_date) do
    next_summary_date =
      :archethic
      |> Application.get_env(SummaryTimer, [])
      |> Keyword.fetch!(:interval)
      |> CronParser.parse!(true)
      |> Utils.next_date(last_sync_date)

    next_repair_date =
      :archethic
      |> Application.get_env(Scheduler, [])
      |> Keyword.fetch!(:interval)
      |> CronParser.parse!(true)
      |> Utils.next_date(next_summary_date)

    DateTime.compare(DateTime.utc_now(), next_repair_date) != :lt
  end

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

  @doc """
  Resync storage_address & io_addresses.
  We use a lock on the genesis_address to avoid running concurrent syncs on the same chain
  """
  @spec resync(
          Crypto.prepended_hash(),
          Crypto.prepended_hash() | list(Crypto.prepended_hash()) | nil,
          list(Crypto.prepended_hash())
        ) :: :ok
  defdelegate resync(genesis_address, storage_address, io_addresses),
    to: RepairWorker,
    as: :repair_addresses

  @doc """
  Replicate the transaction at given address
  """
  @spec replicate_transaction(binary(), boolean()) :: :ok | {:error, term()}
  def replicate_transaction(address, storage? \\ true) do
    # We get the authorized nodes before the last summary date as we are sure that they know
    # the informations we need. Requesting current nodes may ask information to nodes in same repair
    # process as we are here.
    authorized_nodes =
      DateTime.utc_now()
      |> BeaconChain.previous_summary_time()
      |> P2P.authorized_and_available_nodes(true)

    timeout = Message.get_max_timeout()

    acceptance_resolver = fn
      %Transaction{address: ^address} -> true
      _ -> false
    end

    with false <- TransactionChain.transaction_exists?(address),
         storage_nodes <- Election.chain_storage_nodes(address, authorized_nodes),
         {:ok, tx} <-
           TransactionChain.fetch_transaction(address, storage_nodes,
             search_mode: :remote,
             timeout: timeout,
             acceptance_resolver: acceptance_resolver
           ) do
      # TODO: Also download replication attestation from beacon nodes to ensure validity of the transaction
      if storage? do
        :ok = Replication.sync_transaction_chain(tx, authorized_nodes, true)
        update_last_address(address, authorized_nodes)
      else
        Replication.synchronize_io_transaction(tx, true)
      end
    else
      true ->
        {:error, :transaction_already_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the next repair time from the scheduler
  """
  @spec next_repair_time() :: DateTime.t()
  defdelegate next_repair_time, to: Scheduler
end
