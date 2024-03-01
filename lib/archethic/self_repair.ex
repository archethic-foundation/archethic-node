defmodule Archethic.SelfRepair do
  @moduledoc """
  Synchronization for all the Archethic nodes relies on the self-repair mechanism started during
  the bootstrapping phase and stores last synchronization date after each cycle.
  """
  alias Archethic.BeaconChain

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

  alias __MODULE__.Notifier
  alias __MODULE__.NotifierSupervisor
  alias __MODULE__.Scheduler
  alias __MODULE__.Sync
  alias __MODULE__.RepairWorker

  require Logger

  defmodule Error do
    defexception [:function, :message, :address]

    @impl Exception
    def message(%__MODULE__{function: function, message: message, address: nil}) do
      "Self repair encounter an error in function #{function} with error #{message}"
    end

    def message(%__MODULE__{function: function, message: message, address: address}) do
      "Self repair encounter an error in function #{function} on address: #{Base.encode16(address)} with error #{message}"
    end
  end

  @max_retry_count 10

  @doc """
  Start the self repair synchronization scheduler
  """
  @spec start_scheduler() :: :ok
  defdelegate start_scheduler, to: Scheduler

  @doc """
  Start the bootstrap's synchronization process using the last synchronization date
  """
  @spec bootstrap_sync(download_nodes :: list(Node.t())) ::
          :ok | :error
  def bootstrap_sync(download_nodes) do
    case sync_with_retry(download_nodes) do
      :ok ->
        # At the end of self repair, if a new beacon summary as been created
        # we run bootstrap_sync again until the last beacon summary is loaded
        last_sync_date = last_sync_date()

        case DateTime.utc_now()
             |> BeaconChain.previous_summary_time()
             |> DateTime.compare(last_sync_date) do
          :gt ->
            bootstrap_sync(download_nodes)

          _ ->
            :ok
        end

      :error ->
        Logger.error(
          "Bootstrap Sync failed to load missed transactions after max retry of #{@max_retry_count} !"
        )

        :error
    end
  end

  defp sync_with_retry(download_nodes) do
    0..@max_retry_count
    |> Enum.reduce_while(:error, fn _, _ ->
      try do
        Process.flag(:trap_exit, true)
        :ok = last_sync_date() |> Sync.load_missed_transactions(download_nodes)
        {:halt, :ok}
      rescue
        error ->
          Logger.error("Error during bootstrap self repair")
          Logger.error(Exception.format(:error, error, __STACKTRACE__))
          {:cont, :error}
      catch
        :exit, error ->
          Logger.error("Error during bootstrap self repair")
          Logger.error(Exception.format(:error, error, __STACKTRACE__))
          {:cont, :error}
      end
    end)
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
  Determines whether there is a self repair date missed since the last synchronization date

  ## Examples

      iex> SelfRepair.missed_sync?(nil)
      true

      iex> SelfRepair.missed_sync?(~U[2024-02-01 20:00:00Z], "0 0 * * *", "5 * * * * * *", ~U[2024-02-01 20:05:00Z])
      false

      iex> SelfRepair.missed_sync?(~U[2024-02-01 20:00:00Z], "0 0 * * *", "5 * * * * * *", ~U[2024-02-01 22:00:00Z])
      true
  """
  @spec missed_sync?(
          last_sync_date :: DateTime.t() | nil,
          summary_cron_interval :: binary(),
          repair_cron_interval :: binary()
        ) :: boolean()
  def missed_sync?(
        last_sync_date,
        summary_cron_interval \\ BeaconChain.get_summary_interval(),
        repair_cron_interval \\ Scheduler.get_interval(),
        ref_date \\ DateTime.utc_now()
      )

  def missed_sync?(nil, _, _, _), do: true

  def missed_sync?(
        last_sync_date,
        summary_cron_interval,
        repair_cron_interval,
        ref_date
      ) do
    next_repair_date =
      last_sync_date
      |> BeaconChain.next_summary_date(summary_cron_interval)
      |> Scheduler.next_repair_time(repair_cron_interval)

    DateTime.compare(ref_date, next_repair_date) != :lt
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
  Request missing transaction addresses from last local address until last chain address
  and add them in the DB
  """
  def update_last_address(address, authorized_nodes) do
    # As the node is storage node of this chain, it needs to know all the addresses of the chain until the last
    # So we get the local last address and verify if it's the same as the last address of the chain
    # by requesting the nodes which already know the last address

    {last_local_address, _timestamp} = TransactionChain.get_last_address(address)
    storage_nodes = Election.storage_nodes(last_local_address, authorized_nodes)

    case TransactionChain.fetch_next_chain_addresses(last_local_address, storage_nodes,
           search_mode: :remote
         ) do
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
  @spec replicate_transaction(
          address :: Crypto.prepended_hash(),
          genesis_address :: Crypto.prepended_hash(),
          storage? :: boolean()
        ) :: :ok | {:error, term()}
  def replicate_transaction(address, genesis_address, storage? \\ true) do
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
        :ok =
          Replication.sync_transaction_chain(tx, genesis_address, authorized_nodes,
            self_repair?: true
          )

        update_last_address(address, authorized_nodes)
      else
        Replication.synchronize_io_transaction(tx, genesis_address, self_repair?: true)
      end
    else
      true -> {:error, :transaction_already_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the next repair time from the scheduler
  """
  @spec next_repair_time() :: DateTime.t()
  defdelegate next_repair_time, to: Scheduler
end
