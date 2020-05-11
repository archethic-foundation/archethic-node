defmodule UnirisCore.Mining do
  alias UnirisCore.MiningRegistry
  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Beacon
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.Storage
  alias UnirisCore.Crypto
  alias UnirisCore.P2P
  alias __MODULE__.Worker
  alias __MODULE__.WorkerSupervisor
  alias __MODULE__.Replication
  alias __MODULE__.Stamp
  alias __MODULE__.Context

  require Logger

  @doc """
  Start mining process for a given transaction.
  """
  @spec start(
          transaction :: Transaction.pending(),
          welcome_node_public_key :: UnirisCore.Crypto.key(),
          validation_node_public_keys :: list(UnirisCore.Crypto.key())
        ) :: {:ok, pid()} | :ok

  def start(tx = %Transaction{}, _, []) do
    Task.start(fn ->
      %Transaction{} = tx = self_mining(tx)

      UnirisCore.Storage.write_transaction(tx)

      tx.address
      |> Beacon.subset_from_address()
      |> Beacon.add_transaction_info(%TransactionInfo{
        address: tx.address,
        type: tx.type,
        timestamp: tx.timestamp
      })
    end)
  end

  def start(tx = %Transaction{}, _, [_ | []]) do
    Task.start(fn ->
      %Transaction{} = tx = self_mining(tx)

      chain_storage_nodes =
        P2P.list_nodes()
        |> Enum.filter(& &1.available?)
        |> Enum.filter(& &1.ready?)

      beacon_storage_nodes =
        tx.address
        |> Beacon.subset_from_address()
        |> Beacon.get_pool(tx.timestamp)

      Replication.run(tx, chain_storage_nodes, beacon_storage_nodes)
    end)
  end

  def start(tx = %Transaction{}, welcome_node_public_key, validation_node_public_keys) do
    DynamicSupervisor.start_child(WorkerSupervisor, {
      Worker,
      transaction: tx,
      welcome_node_public_key: welcome_node_public_key,
      validation_node_public_keys: validation_node_public_keys,
      node_public_key: Crypto.node_public_key()
    })
  end

  @doc """
  Add a context which has been built by another validation node and provide view of storage and validation nodes.
  """
  @spec add_context(
          address :: binary(),
          validation_node_public_key :: Crypto.key(),
          previous_storage_node_public_keys :: list(Crypto.key()),
          validation_nodes_view :: bitstring(),
          chain_storage_nodes_view :: bitstring(),
          beacon_storage_nodes_view :: bitstring()
        ) ::
          :ok
  def add_context(
        tx_address,
        validation_node_public_key,
        previous_storage_node_public_keys,
        validation_nodes_view,
        chain_storage_nodes_view,
        beacon_storage_nodes_view
      ) do
    Worker.add_context(
      get_worker_pid(tx_address),
      validation_node_public_key,
      previous_storage_node_public_keys,
      validation_nodes_view,
      chain_storage_nodes_view,
      beacon_storage_nodes_view
    )
  end

  @doc """
  Cross validate the validation stamp produced by the coordinator

  If no inconsistencies, the validation stamp is stamped by the the node public key.
  Otherwise the inconsistencies will be signed.

  """
  @spec cross_validate(address :: binary(), ValidateStamp.t()) :: :ok
  def cross_validate(tx_address, stamp = %ValidationStamp{}) do
    Worker.cross_validate(get_worker_pid(tx_address), stamp)
  end

  @doc """
  Set chain storage nodes and beacon storage nodes replication tree according to the position in the replication tree and
   extract the replication nodes is in charge with.
  """
  @spec set_replication_trees(
          address :: binary(),
          chain_storage_tree :: list(bitstring()),
          beacon_storage_tree :: list(bitstring())
        ) :: :ok
  def set_replication_trees(tx_address, chain_storage_tree, beacon_storage_tree)
      when is_list(chain_storage_tree) and is_list(beacon_storage_tree) do
    Worker.set_replication_trees(
      get_worker_pid(tx_address),
      chain_storage_tree,
      beacon_storage_tree
    )
  end

  @doc """
  Add a cross validation stamp to the transaction mining process
  """
  @spec add_cross_validation_stamp(
          binary(),
          stamp ::
            {signature :: binary(), inconsistencies :: list(atom), public_key :: Crypto.key()}
        ) ::
          :ok
  def add_cross_validation_stamp(
        tx_address,
        stamp = {_sig, _inconsistencies, _public_key}
      ) do
    Worker.add_cross_validation_stamp(get_worker_pid(tx_address), stamp)
  end

  def replicate_transaction(tx = %Transaction{}) do
    case Storage.get_transaction(tx.address) do
      {:error, :transaction_not_exists} ->
        case Replication.transaction_validation_only(tx) do
          :ok ->
            Storage.write_transaction(tx)
            Logger.info("Replicate transaction #{Base.encode16(tx.address)}")

          _ ->
            Storage.write_ko_transaction(tx)
            Logger.info("KO transaction #{Base.encode16(tx.address)}")
        end

      _ ->
        :ok
    end
  end

  def replicate_transaction_chain(tx = %Transaction{}) do
    case Storage.get_transaction(tx.address) do
      {:error, :transaction_not_exists} ->
        case Replication.chain_validation(tx) do
          {:ok, chain} ->
            Storage.write_transaction_chain(chain)

          _ ->
            Storage.write_ko_transaction(tx)
            Logger.info("KO transaction #{Base.encode16(tx.address)}")
        end

      _ ->
        :ok
    end
  end

  def replicate_address(tx = %Transaction{}) do
    case Replication.transaction_validation_only(tx) do
      :ok ->
        tx.address
        |> Beacon.subset_from_address()
        |> Beacon.add_transaction_info(%TransactionInfo{
          address: tx.address,
          timestamp: tx.timestamp,
          type: tx.type
        })

      _ ->
        Storage.write_ko_transaction(tx)
        Logger.info("KO transaction #{Base.encode16(tx.address)}")
    end
  end

  defp get_worker_pid(tx_address, attemps \\ 0) do
    case Registry.lookup(MiningRegistry, tx_address) do
      [{pid, _}] ->
        pid

      _ ->
        if attemps < 5 do
          Process.sleep(100)
          get_worker_pid(tx_address, attemps + 1)
        end
    end
  end

  # Called when the network is bootstraping when no nodes or only one in the network
  defp self_mining(tx = %Transaction{}) do
    if Transaction.valid_pending_transaction?(tx) do
      {previous_chain, unspent_outputs, _} = Context.fetch(tx)
      node_public_key = Crypto.node_public_key()

      validation_stamp =
        Stamp.create_validation_stamp(
          tx,
          previous_chain,
          unspent_outputs,
          node_public_key,
          node_public_key,
          [node_public_key],
          [node_public_key]
        )

      cross_validation_stamp = Stamp.create_cross_validation_stamp(validation_stamp, [])

      %{
        tx
        | validation_stamp: validation_stamp,
          cross_validation_stamps: [cross_validation_stamp]
      }
    end
  end
end
