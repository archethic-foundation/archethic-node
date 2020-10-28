defmodule Uniris.SelfRepair.Sync.SlotFinder do
  @moduledoc false

  alias Uniris.BeaconChain.Slot, as: BeaconSlot

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetBeaconSlots

  @type nodes_by_subsets :: list({subset :: binary(), nodes :: list(Node.t())})
  @type slots_by_subsets :: list({subset :: binary(), list(BeaconSlot.t())})

  @doc """
  Retrieve the list of missed beacon slots from a given date.

  It request every subsets to find out the missing ones by query beacon pool nodes.
  """
  @spec get_beacon_slots(nodes_by_subsets(), DateTime.t()) ::
          Enumerable.t() | list(BeaconSlot.t())
  def get_beacon_slots(nodes_by_subsets, last_sync_date = %DateTime{}) do
    Task.async_stream(nodes_by_subsets, fn {subset, nodes} ->
      do_get_beacon_slots(subset, nodes, last_sync_date)
    end)
    |> Stream.map(fn {:ok, res} -> res end)
    |> Stream.transform([], fn slots, acc ->
      {slots, Stream.concat(acc, slots)}
    end)
    |> Stream.uniq()
  end

  defp do_get_beacon_slots(subset, nodes, last_sync_date) do
    nodes
    |> P2P.broadcast_message(%GetBeaconSlots{subset: subset, last_sync_date: last_sync_date})
    |> Stream.take(1)
    |> Stream.flat_map(& &1.slots)
  end
end
