defmodule Archethic.SelfRepair.Notifier.RepairWorker do
  @moduledoc false

  alias Archethic.{
    BeaconChain,
    Election,
    P2P,
    Replication,
    TransactionChain
  }

  alias Archethic.P2P.Message.ShardRepair

  alias Archethic.SelfRepair.Notifier.{
    RepairSupervisor,
    RepairWorker,
    RepairRegistry
  }

  use GenServer, restart: :transient

  require Logger

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
  @spec start_worker(ShardRepair.t()) :: DynamicSupervisor.on_start_child()
  def start_worker(msg) do
    DynamicSupervisor.start_child(RepairSupervisor, {RepairWorker, msg})
  end

  @doc """
  Add a new address in the address list of the RepairWorker
  """
  @spec add_message(pid(), ShardRepair.t()) :: :ok
  def add_message(pid, %ShardRepair{
        storage_address: storage_address,
        io_addresses: io_addresses
      }) do
    GenServer.cast(pid, {:add_address, storage_address, io_addresses})
  end

  def start_link(msg) do
    GenServer.start_link(__MODULE__, msg, [])
  end

  def init(%ShardRepair{
        first_address: first_address,
        storage_address: storage_address,
        io_addresses: io_addresses
      }) do
    Registry.register(RepairRegistry, first_address, [])

    Logger.info(
      "Notifier Repair Worker start with storage_address #{Base.encode16(storage_address)}, " <>
        "io_addresses #{inspect(Enum.map(io_addresses, &Base.encode16(&1)))}",
      address: Base.encode16(first_address)
    )

    authorized_nodes =
      DateTime.utc_now()
      |> BeaconChain.previous_summary_time()
      |> P2P.authorized_and_available_nodes(true)

    storage_addresses = if storage_address != nil, do: [storage_address], else: []

    data = %{
      storage_addresses: storage_addresses,
      io_addresses: io_addresses,
      authorized_nodes: authorized_nodes
    }

    {:ok, start_repair(data)}
  end

  def handle_cast({:add_address, storage_address, io_addresses}, data) do
    new_data =
      if storage_address != nil,
        do: Map.update!(data, :storage_addresses, &([storage_address | &1] |> Enum.uniq())),
        else: data

    new_data =
      if io_addresses != [],
        do: Map.update!(new_data, :io_addresses, &((&1 ++ io_addresses) |> Enum.uniq())),
        else: new_data

    {:noreply, new_data}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _normal},
        data = %{task: task_pid, storage_addresses: [], io_addresses: []}
      )
      when pid == task_pid do
    {:stop, :normal, data}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _normal},
        data = %{task: task_pid}
      )
      when pid == task_pid do
    {:noreply, start_repair(data)}
  end

  def handle_info(_, data), do: {:noreply, data}

  defp start_repair(
         data = %{
           storage_addresses: [],
           io_addresses: [address | rest],
           authorized_nodes: authorized_nodes
         }
       ) do
    pid = repair_task(address, false, authorized_nodes)

    data
    |> Map.put(:io_addresses, rest)
    |> Map.put(:task, pid)
  end

  defp start_repair(
         data = %{
           storage_addresses: [address | rest],
           authorized_nodes: authorized_nodes
         }
       ) do
    pid = repair_task(address, true, authorized_nodes)

    data
    |> Map.put(:storage_addresses, rest)
    |> Map.put(:task, pid)
  end

  defp repair_task(address, storage?, authorized_nodes) do
    %Task{pid: pid} =
      Task.async(fn ->
        replicate_transaction(address, storage?, authorized_nodes)
      end)

    pid
  end

  defp replicate_transaction(address, storage?, authorized_nodes) do
    Logger.debug("Notifier RepairWorker start replication, storage? #{storage?}",
      address: Base.encode16(address)
    )

    with false <- TransactionChain.transaction_exists?(address),
         storage_nodes <- Election.chain_storage_nodes(address, authorized_nodes),
         {:ok, tx} <- TransactionChain.fetch_transaction_remotely(address, storage_nodes) do
      if storage?,
        do: Replication.validate_and_store_transaction_chain(tx, true, authorized_nodes),
        else: Replication.validate_and_store_transaction(tx, true)
    else
      true ->
        Logger.debug("Notifier RepairWorker transaction already exists",
          address: Base.encode16(address)
        )

      {:error, reason} ->
        Logger.warning(
          "Notifier RepairWorker failed to replicate transaction because of #{inspect(reason)}"
        )
    end
  end
end
