defmodule Uniris.BeaconChain.Subset.SlotRegistryTest do
  use UnirisCase

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.NodeInfo
  alias Uniris.BeaconChain.Slot.TransactionInfo
  alias Uniris.BeaconChain.Subset.SlotRegistry

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  alias Uniris.Utils

  doctest SlotRegistry

  test "seal_current_slot/2 should create transaction with current slot" do
    time = DateTime.utc_now()

    slot = %Slot{
      transactions: [
        %TransactionInfo{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :transfer,
          timestamp: DateTime.utc_now() |> Utils.truncate_datetime()
        }
      ]
    }

    %SlotRegistry{slots: slots} =
      SlotRegistry.seal_current_slot(%SlotRegistry{current_slot: slot}, time)

    assert Map.has_key?(slots, time)
    %Transaction{data: %TransactionData{content: content}} = Map.get(slots, time)

    {deserialized_slot, _} = Slot.deserialize(content)
    assert deserialized_slot == slot
  end
end
