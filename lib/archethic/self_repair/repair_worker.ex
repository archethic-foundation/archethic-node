defmodule Archethic.SelfRepair.RepairWorker do
  @moduledoc false

  alias Archethic.SelfRepair
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

    storage_addresses = if storage_address != nil, do: [storage_address], else: []

    data = %{
      storage_addresses: storage_addresses,
      io_addresses: io_addresses
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
           io_addresses: [address | rest]
         }
       ) do
    pid = repair_task(address, false)

    data
    |> Map.put(:io_addresses, rest)
    |> Map.put(:task, pid)
  end

  defp start_repair(
         data = %{
           storage_addresses: [address | rest]
         }
       ) do
    pid = repair_task(address, true)

    data
    |> Map.put(:storage_addresses, rest)
    |> Map.put(:task, pid)
  end

  defp repair_task(address, storage?) do
    %Task{pid: pid} =
      Task.async(fn ->
        SelfRepair.replicate_transaction(address, storage?)
      end)

    pid
  end
end
