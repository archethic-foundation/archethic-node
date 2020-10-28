defmodule Uniris.SelfRepair.Sync.SlotFinderTest do
  use UnirisCase

  alias Uniris.BeaconChain.Slot, as: BeaconSlot
  alias Uniris.BeaconChain.Slot.TransactionInfo

  alias Uniris.P2P
  alias Uniris.P2P.Message.BeaconSlotList
  alias Uniris.P2P.Message.GetBeaconSlots
  alias Uniris.P2P.Node

  alias Uniris.SelfRepair.Sync.SlotFinder

  import Mox

  test "get_beacon_slots/2" do
    node1 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key1",
      last_public_key: "key1"
    }

    node2 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key2",
      last_public_key: "key2"
    }

    node3 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key3",
      last_public_key: "key3"
    }

    node4 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "node4",
      last_public_key: "node4"
    }

    P2P.add_node(node1)
    P2P.add_node(node2)
    P2P.add_node(node3)
    P2P.add_node(node4)

    MockTransport
    |> stub(:send_message, fn
      _, _, %GetBeaconSlots{subset: "A"} ->
        slots = [
          %BeaconSlot{transactions: [%TransactionInfo{address: "@Alice2"}]},
          %BeaconSlot{transactions: [%TransactionInfo{address: "@Bob3"}]}
        ]

        {:ok, %BeaconSlotList{slots: slots}}

      _, _, %GetBeaconSlots{subset: "B"} ->
        slots = [
          %BeaconSlot{transactions: [%TransactionInfo{address: "@Charlie5"}]}
        ]

        {:ok, %BeaconSlotList{slots: slots}}

      _, _, %GetBeaconSlots{subset: "D"} ->
        slots = [
          %BeaconSlot{transactions: [%TransactionInfo{address: "@Alice3"}]},
          %BeaconSlot{transactions: [%TransactionInfo{address: "@Bob1"}]}
        ]

        {:ok, %BeaconSlotList{slots: slots}}

      _, _, %GetBeaconSlots{subset: "E"} ->
        slots = [
          %BeaconSlot{transactions: [%TransactionInfo{address: "@Tom1"}]},
          %BeaconSlot{transactions: [%TransactionInfo{address: "@Sarah4"}]}
        ]

        {:ok, %BeaconSlotList{slots: slots}}

      _, _, %GetBeaconSlots{subset: "F"} ->
        slots = [
          %BeaconSlot{transactions: [%TransactionInfo{address: "@Tom2"}]},
          %BeaconSlot{transactions: [%TransactionInfo{address: "@Bob4"}]}
        ]

        {:ok, %BeaconSlotList{slots: slots}}
    end)

    expected_addresses = [
      "@Alice2",
      "@Bob3",
      "@Charlie5",
      "@Alice3",
      "@Bob1",
      "@Tom1",
      "@Sarah4",
      "@Tom2",
      "@Bob4"
    ]

    transaction_addresses =
      [
        {"A", [node1, node2]},
        {"B", [node1, node2]},
        {"D", [node1]},
        {"E", [node2, node1]},
        {"F", [node2]}
      ]
      |> SlotFinder.get_beacon_slots(DateTime.utc_now())
      |> Enum.flat_map(& &1.transactions)
      |> Enum.map(& &1.address)

    assert Enum.all?(expected_addresses, &(&1 in transaction_addresses))
  end
end
