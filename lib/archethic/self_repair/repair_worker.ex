defmodule Archethic.SelfRepair.RepairWorker do
  @moduledoc false

  alias Archethic.{
    BeaconChain,
    Election,
    P2P,
    Replication,
    TransactionChain,
    SelfRepair
  }

  alias Archethic.P2P.Message
  alias Archethic.TransactionChain.Transaction

  alias Archethic.SelfRepair.RepairRegistry

  use GenServer, restart: :transient
  @vsn Mix.Project.config()[:version]

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    first_address = Keyword.fetch!(args, :first_address)
    storage_address = Keyword.fetch!(args, :storage_address)
    io_addresses = Keyword.fetch!(args, :io_addresses)

    Registry.register(RepairRegistry, first_address, [])

    Logger.info(
      "Notifier Repair Worker start with storage_address #{if storage_address, do: Base.encode16(storage_address), else: nil}, " <>
        "io_addresses #{inspect(Enum.map(io_addresses, &Base.encode16(&1)))}",
      address: Base.encode16(first_address)
    )

    # We get the authorized nodes before the last summary date as we are sure that they know
    # the informations we need. Requesting current nodes may ask information to nodes in same repair
    # process as we are here.
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

    timeout = Message.get_max_timeout()

    acceptance_resolver = fn
      {:ok, %Transaction{address: ^address}} -> true
      _ -> false
    end

    with false <- TransactionChain.transaction_exists?(address),
         storage_nodes <- Election.chain_storage_nodes(address, authorized_nodes),
         {:ok, tx} <-
           TransactionChain.fetch_transaction_remotely(
             address,
             storage_nodes,
             timeout,
             acceptance_resolver
           ) do
      # TODO: Also download replication attestation from beacon nodes to ensure validity of the transaction
      if storage? do
        :ok = Replication.sync_transaction_chain(tx, authorized_nodes, true)
        SelfRepair.update_last_address(address, authorized_nodes)
      else
        Replication.synchronize_io_transaction(tx, true)
      end
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
