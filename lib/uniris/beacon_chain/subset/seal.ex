defmodule Uniris.BeaconChain.Subset.Seal do
  @moduledoc false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Summary

  alias Uniris.Crypto

  alias Uniris.DB

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetBeaconSlot
  alias Uniris.P2P.Message.NotFound

  require Logger

  @doc """
  Link the current slot to the previous one by computing the previous hash from the previous slot

  If the previous slot doesn't exists it will used the default previous hash (list of zeros)
  """
  @spec link_to_previous_slot(Slot.t(), DateTime.t()) :: Slot.t()
  def link_to_previous_slot(slot = %Slot{subset: subset}, previous_slot_time = %DateTime{}) do
    case previous_storage_nodes(subset, previous_slot_time) do
      [] ->
        slot

      nodes ->
        case fetch_slot(nodes, subset, previous_slot_time) do
          {:ok, prev_slot} ->
            previous_hash =
              prev_slot
              |> Slot.serialize()
              |> Crypto.hash()

            %{slot | previous_hash: previous_hash}

          _ ->
            slot
        end
    end
  end

  defp fetch_slot(nodes, subset, previous_slot_time) do
    case P2P.reply_first(nodes, %GetBeaconSlot{
           subset: subset,
           slot_time: previous_slot_time
         }) do
      {:ok, prev_slot = %Slot{}} ->
        {:ok, prev_slot}

      {:ok, %NotFound{}} ->
        {:error, :not_found}

      {:error, _} = e ->
        e
    end
  end

  defp previous_storage_nodes(subset, slot_time = %DateTime{}) when is_binary(subset) do
    Election.beacon_storage_nodes(
      subset,
      slot_time,
      P2P.list_nodes(availability: :global),
      Election.get_storage_constraints()
    )
    |> Enum.filter(&(DateTime.compare(&1.enrollment_date, slot_time) == :lt))
  end

  @doc """
  Create a new beacon chain summary by aggregating the previous stored slots (from differents slot times)
  and the current beacon slot to be stored in the database
  """
  @spec new_summary(binary(), DateTime.t(), Slot.t()) :: :ok
  def new_summary(subset, summary_time = %DateTime{}, current_slot = %Slot{})
      when is_binary(subset) do
    beacon_slots = DB.get_beacon_slots(subset, summary_time) |> Stream.concat([current_slot])

    if Enum.count(beacon_slots) > 0 do
      %Summary{subset: subset, summary_time: summary_time}
      |> Summary.aggregate_slots(beacon_slots)
      |> DB.register_beacon_summary()
    else
      :ok
    end
  end
end
