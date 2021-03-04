defmodule Uniris.BeaconChain.Subset.Seal do
  @moduledoc false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.Summary

  alias Uniris.Crypto

  alias Uniris.DB

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetBeaconSlot

  require Logger

  @doc """
  Link the current slot to the previous one by computing the previous hash from the previous slot
  """
  @spec link_to_previous_slot(Slot.t()) :: Slot.t()
  def link_to_previous_slot(slot = %Slot{subset: subset, slot_time: slot_time}) do
    previous_slot_time = SlotTimer.previous_slot(slot_time)
    previous_storage_nodes = previous_storage_nodes(subset, previous_slot_time)

    case fetch_previous_slot(subset, previous_slot_time, previous_storage_nodes) do
      prev_slot = %Slot{} ->
        previous_hash =
          prev_slot
          |> Slot.serialize()
          |> Crypto.hash()

        %{slot | previous_hash: previous_hash}

      _ ->
        slot
    end
  end

  defp previous_storage_nodes(subset, slot_time = %DateTime{}) when is_binary(subset) do
    Election.beacon_storage_nodes(
      subset,
      slot_time,
      P2P.list_nodes(availability: :global),
      Election.get_storage_constraints()
    )
  end

  defp fetch_previous_slot(subset, slot_time = %DateTime{}, storage_nodes)
       when is_binary(subset) and is_list(storage_nodes) do
    {:ok, slot} =
      P2P.reply_first(storage_nodes, %GetBeaconSlot{subset: subset, slot_time: slot_time})

    slot
  end

  @spec new_summary(binary(), DateTime.t()) :: :ok
  def new_summary(subset, summary_time = %DateTime{}) when is_binary(subset) do
    beacon_slots = DB.get_beacon_slots(subset, summary_time)

    if Enum.count(beacon_slots) > 0 do
      %Summary{subset: subset, summary_time: summary_time}
      |> Summary.aggregate_slots(beacon_slots)
      |> DB.register_beacon_summary()
    else
      :ok
    end
  end
end
