defmodule Uniris.TransactionChainTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  doctest TransactionChain

  import Mox

  test "resolve_last_address/1 should retrieve the last address for a chain" do
    MockDB
    |> stub(:get_last_chain_address, fn
      _, ~U[2021-03-25 15:11:29Z] ->
        "@Alice1"

      _, ~U[2021-03-25 15:12:29Z] ->
        "@Alice2"
    end)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(0),
      available?: true,
      geo_patch: "AAA"
    })

    assert "@Alice1" = TransactionChain.resolve_last_address("@Alice1", ~U[2021-03-25 15:11:29Z])
    assert "@Alice2" = TransactionChain.resolve_last_address("@Alice1", ~U[2021-03-25 15:12:29Z])
  end
end
