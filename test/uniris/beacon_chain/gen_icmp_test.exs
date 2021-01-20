defmodule Uniris.BeaconChain.GenICMPTest do
  use UnirisCase

  alias Uniris.BeaconChain.GenICMP
  alias Uniris.P2P
  alias Uniris.P2P.Node

  doctest GenICMP

  test "ping/1 should ping the destination node" do
    assert {:ok, %{data: <<222, 173, 190, 239>>, id: 0, seq: 0}} = GenICMP.ping({127, 0, 0, 1})
  end

  test "ping/1 should ping multiple destinations" do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3005,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3002,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3005,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true
    })

    p2p_view_available = Enum.map(P2P.list_nodes(), fn x -> GenICMP.ping(x.ip) end)

    assert [
             {:ok, %{data: <<222, 173, 190, 239>>, id: 0, seq: 0}},
             {:ok, %{data: <<222, 173, 190, 239>>, id: 0, seq: 0}},
             {:ok, %{data: <<222, 173, 190, 239>>, id: 0, seq: 0}}
           ] = p2p_view_available
  end
end
