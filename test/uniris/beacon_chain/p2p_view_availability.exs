defmodule Uniris.BeaconChain.P2PViewAvailability do
  use UnirisCase

  alias Uniris.P2P
  alias Uniris.P2P.Node
  alias Uniris.P2P.Message.Ok

  test "ping/1 should ping the destination node" do
    node = %Node{
      ip: {127, 0, 0, 1},
      port: 3005,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true
    }

    MockClient
    |> expect(:health_check, fn _, %HeathCheackRequest{}, _ ->
      {:ok, %HeathCheackRequest{}}
    end)

    assert {:ok, <<255>>} = P2P.wl(node, %Ok{})
  end
end
