defmodule UnirisCore.BeaconTest do
  use UnirisCoreCase
  doctest UnirisCore.Beacon

  alias UnirisCore.Beacon
  alias UnirisCore.BeaconSubsets
  alias UnirisCore.BeaconSlotTimer
  alias UnirisCore.BeaconSubset
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node

  setup do
    start_supervised!({BeaconSlotTimer, slot_interval: 100})
    Enum.map(BeaconSubsets.all(), &start_supervised({BeaconSubset, subset: &1}, id: &1))
    :ok
  end

  test "get_pool/2 should get the authorized and storage nodes for the beacon derivated address" do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key1",
      last_public_key: "key1",
      authorized?: true,
      ready?: true,
      enrollment_date: DateTime.utc_now(),
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
      ready?: true,
      enrollment_date: DateTime.utc_now(),
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
      enrollment_date: DateTime.utc_now() |> DateTime.add(86400),
      available?: true,
      average_availability: 1,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    assert [%Node{first_public_key: "key1"}] = Beacon.get_pool(<<0>>, DateTime.utc_now())
  end

  test "get_pools/1 should get all the subsets nodes from a last date" do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key1",
      last_public_key: "key1",
      authorized?: true,
      ready?: true,
      enrollment_date: DateTime.utc_now(),
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
      ready?: true,
      enrollment_date: DateTime.utc_now() |> DateTime.add(1),
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
      enrollment_date: DateTime.utc_now() |> DateTime.add(2),
      available?: true,
      average_availability: 1,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    assert Enum.all?(Beacon.get_pools(DateTime.utc_now()), fn {_, nodes} -> length(nodes) == 1 end)

    assert Enum.all?(Beacon.get_pools(DateTime.utc_now() |> DateTime.add(1)), fn {_, nodes} ->
             length(nodes) == 2
           end)

    assert Enum.all?(Beacon.get_pools(DateTime.utc_now() |> DateTime.add(2)), fn {_, nodes} ->
             length(nodes) == 3
           end)

    assert length(Beacon.get_pools(DateTime.utc_now())) == 255
  end

  test "all_subsets/0 should return 255 subsets" do
    assert Enum.map(0..254, &:binary.encode_unsigned(&1)) == Beacon.all_subsets()
  end
end
