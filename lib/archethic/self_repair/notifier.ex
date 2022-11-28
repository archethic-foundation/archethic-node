defmodule Archethic.SelfRepair.Notifier do
  @moduledoc false
  alias Archethic.Crypto

  alias Archethic.P2P.Message.ShardRepair
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.NotifierSupervisor

  alias __MODULE__.Impl
  alias __MODULE__.RepairWorker
  alias __MODULE__.RepairRegistry

  @spec start_notifier(list(Node.t()), list(Node.t()), DateTime.t()) :: :ok
  def start_notifier(prev_available_nodes, new_available_nodes, availability_update) do
    diff_node =
      (prev_available_nodes -- new_available_nodes)
      |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))

    case diff_node do
      [] ->
        :ok

      nodes ->
        unavailable_nodes = Enum.map(nodes, & &1.first_public_key)

        DynamicSupervisor.start_child(
          NotifierSupervisor,
          {Impl,
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
  @spec start_worker(ShardRepair.t()) :: DynamicSupervisor.on_start_child()
  def start_worker(msg) do
    DynamicSupervisor.start_child(NotifierSupervisor, {RepairWorker, msg})
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
end
