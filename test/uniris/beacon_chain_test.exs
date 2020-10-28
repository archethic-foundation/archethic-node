defmodule Uniris.BeaconChainTest do
  use UnirisCase

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.Subset

  alias Uniris.P2P
  alias Uniris.P2P.Node

  doctest Uniris.BeaconChain

  setup do
    Enum.map(BeaconChain.list_subsets(), &start_supervised({Subset, subset: &1}, id: &1))
    start_supervised!({SlotTimer, interval: "0 * * * * * *", trigger_offset: 0})
    :ok
  end

  describe "get_pool/2 should get the authorized storage nodes for the beacon derived address before a given date" do
    test "with 2 authorized nodes before the given date" do
      date_ref = DateTime.utc_now()

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: DateTime.add(date_ref, -5),
        enrollment_date: DateTime.add(date_ref, -20),
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
        authorization_date: DateTime.add(date_ref, -5),
        enrollment_date: DateTime.add(date_ref, -30),
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
        authorization_date: DateTime.add(date_ref, -5),
        enrollment_date: DateTime.add(date_ref, -50),
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      node_keys = BeaconChain.get_pool(<<0>>, date_ref) |> Enum.map(& &1.first_public_key)
      assert Enum.all?(["key3", "key1"], &(&1 in node_keys))
    end

    test "with 3 authorized nodes before the given date" do
      date_ref = ~U[2020-09-01 14:33:51.710810Z]

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: DateTime.add(date_ref, -5),
        enrollment_date: DateTime.add(date_ref, -20),
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
        authorization_date: DateTime.add(date_ref, -5),
        enrollment_date: DateTime.add(date_ref, -30),
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
        authorization_date: DateTime.add(date_ref, -5),
        enrollment_date: DateTime.add(date_ref, -50),
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      node_keys = BeaconChain.get_pool(<<0>>, date_ref) |> Enum.map(& &1.first_public_key)
      assert Enum.all?(["key3", "key2", "key1"], &(&1 in node_keys))
    end
  end

  describe "get_pools/1" do
    test "should get one node where his authorization is older than 1 minute" do
      date_ref = DateTime.utc_now()

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: DateTime.add(date_ref, -60),
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      next_slot_beacon_pool = BeaconChain.get_pools(DateTime.add(date_ref, -60))

      assert Enum.all?(next_slot_beacon_pool, fn {_, nodes} ->
               assert [%Node{first_public_key: "key1"}] = nodes
             end)

      assert length(next_slot_beacon_pool) == 256
    end

    test "should get two node where their authorization are older than 2 minutes" do
      date_ref = DateTime.utc_now()

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: DateTime.add(date_ref, -120),
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
        authorization_date: DateTime.add(date_ref, -60),
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
        authorization_date: date_ref,
        available?: true,
        average_availability: 1,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      next_slot_beacon_pool = BeaconChain.get_pools(DateTime.add(date_ref, -120))

      assert Enum.all?(next_slot_beacon_pool, fn {_, nodes} ->
               assert length(nodes) == 2
               node_keys = Enum.map(nodes, & &1.first_public_key)
               assert Enum.all?(["key1", "key2"], &(&1 in node_keys))
             end)

      assert length(next_slot_beacon_pool) == 256
    end
  end

  test "all_subsets/0 should return 256 subsets" do
    assert Enum.map(0..255, &:binary.encode_unsigned(&1)) == BeaconChain.list_subsets()
  end
end
