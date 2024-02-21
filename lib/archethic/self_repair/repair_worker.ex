defmodule Archethic.SelfRepair.RepairWorker do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.RepairRegistry
  alias Archethic.SelfRepair.NotifierSupervisor

  use GenServer, restart: :transient
  @vsn 2

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [])
  end

  @doc """
  Add addresses to repair in RepairWorker.
  If the RepairWorker does not exist yet, it is created.
  The RepairWorker will run until there is no more address to repair.
  """
  @spec repair_addresses(
          Crypto.prepended_hash(),
          Crypto.prepended_hash() | list(Crypto.prepended_hash()) | nil,
          list(Crypto.prepended_hash())
        ) :: :ok
  def repair_addresses(genesis_address, storage_addresses, io_addresses) do
    storage_addresses = List.wrap(storage_addresses)

    case Registry.lookup(RepairRegistry, genesis_address) do
      [{pid, _}] ->
        GenServer.cast(pid, {:add_address, storage_addresses, io_addresses})

      _ ->
        {:ok, _} =
          DynamicSupervisor.start_child(
            NotifierSupervisor,
            {__MODULE__,
             [
               genesis_address: genesis_address,
               storage_addresses: storage_addresses,
               io_addresses: io_addresses
             ]}
          )

        :ok
    end
  end

  def init(args) do
    genesis_address = Keyword.fetch!(args, :genesis_address)
    storage_addresses = Keyword.fetch!(args, :storage_addresses)
    io_addresses = Keyword.fetch!(args, :io_addresses)

    Registry.register(RepairRegistry, genesis_address, [])

    Logger.info(
      "Notifier Repair Worker start with storage_addresses #{Enum.map_join(storage_addresses, ", ", &Base.encode16(&1))}, " <>
        "io_addresses #{inspect(Enum.map(io_addresses, &Base.encode16(&1)))}",
      address: Base.encode16(genesis_address)
    )

    data = %{
      storage_addresses: storage_addresses,
      io_addresses: io_addresses,
      genesis_address: genesis_address
    }

    {:ok, start_repair(data)}
  end

  def handle_cast({:add_address, storage_addresses, io_addresses}, data) do
    new_data =
      if storage_addresses != [],
        do: Map.update!(data, :storage_addresses, &((&1 ++ storage_addresses) |> Enum.uniq())),
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

  # add the genesis_address to the state
  def code_change(1, state, _extra) do
    [genesis_address] = Registry.keys(RepairRegistry, self())
    state = Map.put(state, :genesis_address, genesis_address)
    {:ok, state}
  end

  def code_change(_version, state, _extra), do: {:ok, state}

  defp start_repair(
         data = %{
           storage_addresses: [],
           io_addresses: [address | rest],
           genesis_address: genesis_address
         }
       ) do
    pid = repair_task(address, genesis_address, false)

    data
    |> Map.put(:io_addresses, rest)
    |> Map.put(:task, pid)
  end

  defp start_repair(
         data = %{
           storage_addresses: [address | rest],
           genesis_address: genesis_address
         }
       ) do
    pid = repair_task(address, genesis_address, true)

    data
    |> Map.put(:storage_addresses, rest)
    |> Map.put(:task, pid)
  end

  defp repair_task(address, genesis_address, storage?) do
    %Task{pid: pid} =
      Task.async(fn ->
        SelfRepair.replicate_transaction(address, genesis_address, storage?)
      end)

    pid
  end
end
