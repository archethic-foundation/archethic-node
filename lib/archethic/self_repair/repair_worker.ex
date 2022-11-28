defmodule Archethic.SelfRepair.RepairWorker do
  @moduledoc false

  alias Archethic.{
    Contracts,
    BeaconChain,
    Election,
    P2P,
    Replication,
    TransactionChain
  }

  alias Archethic.SelfRepair.RepairRegistry

  use GenServer, restart: :transient

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
      "Notifier Repair Worker start with storage_address #{Base.encode16(storage_address)}, " <>
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

    with false <- TransactionChain.transaction_exists?(address),
         storage_nodes <- Election.chain_storage_nodes(address, authorized_nodes),
         {:ok, tx} <- TransactionChain.fetch_transaction_remotely(address, storage_nodes) do
      if storage? do
        case Replication.validate_and_store_transaction_chain(tx, true, authorized_nodes) do
          :ok -> update_last_address(address, authorized_nodes)
          error -> error
        end
      else
        Replication.validate_and_store_transaction(tx, true)
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
end
