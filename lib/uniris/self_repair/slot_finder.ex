defmodule Uniris.SelfRepair.SlotFinder do
  @moduledoc false

  alias Uniris.Beacon
  alias Uniris.BeaconSlot

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetBeaconSlots

  alias Uniris.TaskSupervisor

  @doc """
  Retrieve the missing slots for a given date.

  Node patch is used to fetch the closest nodes from it
  """
  @spec missing_slots(DateTime.t(), binary()) :: list(BeaconSlot.t())
  def missing_slots(last_sync_date = %DateTime{}, node_patch) do
    Beacon.get_pools(last_sync_date)
    |> closest_nodes(node_patch)
    |> group_subsets_by_node()
    |> get_beacon_slots(last_sync_date)
  end

  # Request beacon pools the slot informations before the last synchronization time
  defp get_beacon_slots(slot_batches, last_sync_date) do
    TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(slot_batches, fn {node, subsets} ->
      P2P.send_message(node, %GetBeaconSlots{subsets: subsets, last_sync_date: last_sync_date})
    end)
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.flat_map(& &1.slots)
    |> Enum.uniq()
  end

  defp closest_nodes(_subsets_and_nodes, _node_patch, acc \\ [])

  defp closest_nodes([{subset, nodes} | rest], node_patch, acc) do
    nearest_nodes =
      nodes
      |> P2P.nearest_nodes(node_patch)
      |> Enum.take(1)

    closest_nodes(rest, node_patch, [{subset, nearest_nodes} | acc])
  end

  defp closest_nodes([], _node_patch, acc), do: acc

  defp group_subsets_by_node(_subsets_and_nodes, acc \\ %{})

  defp group_subsets_by_node([{subset, nodes} | rest], acc) do
    acc =
      Enum.reduce(nodes, acc, fn node, acc ->
        Map.update(acc, node, [subset], &[subset | &1])
      end)

    group_subsets_by_node(rest, acc)
  end

  defp group_subsets_by_node([], acc), do: acc
end
