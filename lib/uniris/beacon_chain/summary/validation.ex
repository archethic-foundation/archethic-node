defmodule Uniris.BeaconChain.SummaryValidation do
  @moduledoc false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.SummaryTimer

  alias Uniris.DB

  alias Uniris.Crypto
  alias Uniris.Election

  alias Uniris.P2P

  alias Uniris.Utils

  @doc """
  Determines if the node is a storage node for the beacon summary
  """
  @spec storage_node?(Slot.t()) :: boolean()
  def storage_node?(%Slot{subset: subset, slot_time: slot_time}) do
    summary_time = SummaryTimer.next_summary(slot_time)

    storage_nodes =
      Election.beacon_storage_nodes(
        subset,
        summary_time,
        P2P.list_nodes(availability: :global),
        Election.get_storage_constraints()
      )

    Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0))
  end

  @doc """
  Determines if slot previous hash is valid.

  Without previous slots, it expects to be the genesis one
  Otherwise the previous slot will be compared
  """
  @spec valid_previous_hash?(Slot.t()) :: boolean()
  def valid_previous_hash?(%Slot{previous_hash: hash, subset: subset, slot_time: slot_time}) do
    previous_slot_time = SlotTimer.previous_slot(slot_time)

    case DB.get_beacon_slot(subset, previous_slot_time) do
      {:ok, slot} ->
        previous_hash =
          slot
          |> Slot.serialize()
          |> Crypto.hash()

        hash == previous_hash

      {:error, :not_found} ->
        hash == Slot.genesis_previous_hash()
    end
  end

  @doc """
  Determines if all the signatures from the beacon slot are valid according to the list of involved nodes.

  Each involved node is retrieved by performing a lookup to find out 
  the storage node public key based on the position of the bits

  By checking all we are ensuring the atomic commitment of the beacon slot creation
  """
  @spec valid_signatures?(Slot.t()) :: boolean()
  def valid_signatures?(
        slot = %Slot{
          slot_time: slot_time,
          subset: subset,
          validation_signatures: validation_signatures
        }
      ) do
    storage_nodes = slot_storage_nodes_keys(subset, slot_time)

    Enum.all?(validation_signatures, fn {pos, signature} ->
      case Enum.at(storage_nodes, pos) do
        nil ->
          false

        node_key ->
          Crypto.verify(signature, Slot.digest(slot), node_key)
      end
    end)
  end

  defp slot_storage_nodes_keys(subset, slot_time) do
    subset
    |> Election.beacon_storage_nodes(
      slot_time,
      P2P.list_nodes(availability: :global),
      Election.get_storage_constraints()
    )
    |> Enum.map(& &1.last_public_key)
  end
end
