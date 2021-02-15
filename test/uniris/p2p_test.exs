defmodule Uniris.P2PTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Node

  doctest Uniris.P2P

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  test "get_node_info/0 should return retrieve local node information" do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key()
    })

    Process.sleep(100)

    assert %Node{ip: {127, 0, 0, 1}} = P2P.get_node_info()
  end
end
