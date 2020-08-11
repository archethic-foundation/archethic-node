defmodule Uniris.BeaconTest do
  use UnirisCase
  doctest Uniris.Beacon

  alias Uniris.Beacon
  alias Uniris.BeaconSlotTimer
  alias Uniris.BeaconSubset
  alias Uniris.BeaconSubsets
  alias Uniris.P2P
  alias Uniris.P2P.Node

  setup do
    Enum.map(BeaconSubsets.all(), &start_supervised({BeaconSubset, subset: &1}, id: &1))
    start_supervised!({BeaconSlotTimer, interval: "* * * * * *", trigger_offset: 0})
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

  describe "get_pools/1" do
    test "should get one node where his authorization is older than 1 minute" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-60),
        ready?: true,
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      next_slot_beacon_pool = Beacon.get_pools(DateTime.utc_now() |> DateTime.add(-60))

      assert Enum.all?(next_slot_beacon_pool, fn {_, nodes} ->
               assert [%Node{first_public_key: "key1"}] = nodes
             end)

      assert length(next_slot_beacon_pool) == 256
    end

    test "should get two node where their authorization are older than 2 minutes" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-120),
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
        authorization_date: DateTime.utc_now() |> DateTime.add(-60),
        ready?: true,
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      next_slot_beacon_pool = Beacon.get_pools(DateTime.utc_now() |> DateTime.add(-120))

      assert Enum.all?(next_slot_beacon_pool, fn {_, nodes} ->
               assert [
                        %Node{first_public_key: "key1"},
                        %Node{first_public_key: "key2"}
                      ] = nodes
             end)

      assert length(next_slot_beacon_pool) == 256
    end
  end

  test "all_subsets/0 should return 256 subsets" do
    assert Enum.map(0..255, &:binary.encode_unsigned(&1)) == Beacon.all_subsets()
  end
end
