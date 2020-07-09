defmodule UnirisCore.BeaconTest do
  use UnirisCoreCase
  doctest UnirisCore.Beacon

  alias UnirisCore.Beacon
  alias UnirisCore.BeaconSlotTimer
  alias UnirisCore.BeaconSubset
  alias UnirisCore.BeaconSubsets
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.Utils

  setup do
    Enum.map(BeaconSubsets.all(), &start_supervised({BeaconSubset, subset: &1}, id: &1))
    start_supervised!({BeaconSlotTimer, interval: 10_000, trigger_offset: 100})
    :ok
  end

  describe "get_pool/2 should get the authorized storage nodes for the beacon derivated address before a given date" do
    test "with 2 authorized nodes before the given date" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-5),
        ready?: true,
        enrollment_date: DateTime.utc_now() |> DateTime.add(-20),
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key2",
        last_public_key: "key2",
        authorized?: false,
        authorization_date: DateTime.utc_now() |> DateTime.add(-5),
        ready?: true,
        enrollment_date: DateTime.utc_now() |> DateTime.add(-30),
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-5),
        ready?: true,
        enrollment_date: DateTime.utc_now() |> DateTime.add(-50),
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      assert [%Node{first_public_key: "key1"}, %Node{first_public_key: "key3"}] =
               Beacon.get_pool(<<0>>, DateTime.utc_now())
    end

    test "with 3 authorized nodes before the given date" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-5),
        ready?: true,
        enrollment_date: DateTime.utc_now() |> DateTime.add(-20),
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key2",
        last_public_key: "key2",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-5),
        ready?: true,
        enrollment_date: DateTime.utc_now() |> DateTime.add(-30),
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-5),
        ready?: true,
        enrollment_date: DateTime.utc_now() |> DateTime.add(-50),
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      assert [
               %Node{first_public_key: "key1"},
               %Node{first_public_key: "key2"},
               %Node{first_public_key: "key3"}
             ] = Beacon.get_pool(<<0>>, DateTime.utc_now())
    end
  end

  test "get_pools/1 should get all the subsets nodes from a last date" do
    date_ref = Utils.truncate_datetime(DateTime.utc_now())

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key1",
      last_public_key: "key1",
      authorized?: true,
      authorization_date: date_ref,
      ready?: true,
      available?: true,
      average_availability: 1,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key2",
      last_public_key: "key2",
      authorized?: true,
      authorization_date: Utils.truncate_datetime(DateTime.add(date_ref, 10)),
      ready?: true,
      available?: true,
      average_availability: 1,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key3",
      last_public_key: "key3",
      authorized?: true,
      ready?: true,
      authorization_date: Utils.truncate_datetime(DateTime.add(date_ref, 20)),
      available?: true,
      average_availability: 1,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    current_slot_beacon_pool = Beacon.get_pools(Utils.truncate_datetime(DateTime.utc_now()))
    next_slot_beacon_pool = Beacon.get_pools(Utils.truncate_datetime(DateTime.add(date_ref, 10)))
    next_slot_beacon_pool2 = Beacon.get_pools(Utils.truncate_datetime(DateTime.add(date_ref, 20)))
    next_slot_beacon_pool3 = Beacon.get_pools(DateTime.utc_now() |> DateTime.add(30))

    assert current_slot_beacon_pool == []

    assert Enum.all?(next_slot_beacon_pool, fn {_, slots} ->
             assert length(slots) == 1
             {_, [%Node{first_public_key: "key1"}]} = Enum.at(slots, 0)
           end)

    assert Enum.all?(next_slot_beacon_pool2, fn {_, slots} ->
             assert length(slots) == 2

             {_, [%Node{first_public_key: "key1"}, %Node{first_public_key: "key2"}]} =
               Enum.at(slots, 0)

             {_, [%Node{first_public_key: "key1"}]} = Enum.at(slots, 1)
           end)

    assert Enum.all?(next_slot_beacon_pool3, fn {_, slots} ->
             assert length(slots) == 3

             {_,
              [
                %Node{first_public_key: "key1"},
                %Node{first_public_key: "key2"},
                %Node{first_public_key: "key3"}
              ]} = Enum.at(slots, 0)

             {_, [%Node{first_public_key: "key1"}, %Node{first_public_key: "key2"}]} =
               Enum.at(slots, 1)

             {_, [%Node{first_public_key: "key1"}]} = Enum.at(slots, 2)
           end)

    assert length(next_slot_beacon_pool) == length(next_slot_beacon_pool2)
    assert length(next_slot_beacon_pool) == length(next_slot_beacon_pool3)
    assert length(next_slot_beacon_pool) == 256
  end

  test "all_subsets/0 should return 256 subsets" do
    assert Enum.map(0..255, &:binary.encode_unsigned(&1)) == Beacon.all_subsets()
  end
end
