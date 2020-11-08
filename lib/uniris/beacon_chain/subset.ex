defmodule Uniris.BeaconChain.Subset do
  @moduledoc """
  Represents a beacon subset running inside a process
  waiting to receive transactions to register in a beacon block
  through the several slots (time based)
  """

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.NodeInfo
  alias Uniris.BeaconChain.Slot.TransactionInfo
  alias __MODULE__.SlotRegistry
  alias Uniris.BeaconChain.SubsetRegistry
  alias Uniris.PubSub
  alias Uniris.TransactionChain.Transaction
  alias Uniris.P2P

  use GenServer

  require Logger

  def start_link(opts) do
    subset = Keyword.get(opts, :subset)
    GenServer.start_link(__MODULE__, [subset], name: via_tuple(subset))
  end

  def init([subset]) do
    {:ok,
     %{
       subset: subset,
       slot_registry: %SlotRegistry{}
     }}
  end

  def handle_call(
        {:add_transaction_info, tx_info = %TransactionInfo{address: address, type: type}},
        _from,
        state = %{slot_registry: slot_registry, subset: subset}
      ) do
    if SlotRegistry.has_transaction?(slot_registry, address) do
      {:reply, :ok, state}
    else
      Logger.info("Transaction #{type}@#{Base.encode16(address)} info added",
        beacon_subset: Base.encode16(subset)
      )

      PubSub.notify_new_transaction(address)

      new_registry = SlotRegistry.add_transaction_info(slot_registry, tx_info)
      {:reply, :ok, %{state | slot_registry: new_registry}}
    end
  end

  def handle_call(
        {:add_node_info, node_info = %NodeInfo{}},
        _from,
        state = %{slot_registry: slot_registry, subset: subset}
      ) do
    Logger.info("Node #{inspect(node_info)} info added", beacon_subset: Base.encode16(subset))

    new_registry = SlotRegistry.add_node_info(slot_registry, node_info)
    {:reply, :ok, %{state | slot_registry: new_registry}}
  end

  def handle_call(
        {:get_missing_slots, last_sync_date},
        _,
        state = %{slot_registry: slot_registry}
      ) do
    slots = SlotRegistry.slots_after(slot_registry, last_sync_date)
    {:reply, slots, state}
  end

  def handle_info(
        {:create_slot, _slot_time},
        state = %{current_slot: %Slot{transactions: [], nodes: []}}
      ) do
    {:noreply, state}
  end

  def handle_info(
        {:create_slot, slot_time = %DateTime{}},
        state = %{slot_registry: slot_registry, subset: subset}
      ) do

    listNodes =  Enum.filter(P2P.list_nodes(), fn x -> :binary.part(x.first_public_key, 0, 1) == subset end)

    _p2p_view_available = Enum.map(listNodes , fn x -> GenICMP.ping(x) end)
    new_registry = SlotRegistry.seal_current_slot(slot_registry, slot_time)

    {:noreply, %{state | slot_registry: new_registry}}
  end

  @doc """
  Add transaction information to the current block of the given subset
  """
  @spec add_transaction_info(subset :: binary(), Transaction.info()) :: :ok
  def add_transaction_info(subset, tx_info = %TransactionInfo{}) when is_binary(subset) do
    GenServer.call(via_tuple(subset), {:add_transaction_info, tx_info})
  end

  @doc """
  Add node information to the current block of the given subset
  """
  @spec add_node_info(subset :: binary(), NodeInfo.t()) :: :ok
  def add_node_info(subset, node_info = %NodeInfo{}) when is_binary(subset) do
    GenServer.call(via_tuple(subset), {:add_node_info, node_info})
  end

  @doc """
  Get the last information from a beacon subset slot after the last synchronized date
  """
  @spec missing_slots(binary(), last_sync_date :: DateTime.t()) :: list(Slot.t())
  def missing_slots(subset, last_sync_date = %DateTime{}) when is_binary(subset) do
    subset
    |> via_tuple
    |> GenServer.call({:get_missing_slots, last_sync_date})
  end

  defp via_tuple(subset) do
    {:via, Registry, {SubsetRegistry, subset}}
  end
end
