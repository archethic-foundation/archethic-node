defmodule Uniris.TransactionChainTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.GetLastTransactionAddress
  alias Uniris.P2P.Message.LastTransactionAddress
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.MemTables.ChainLookup
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  doctest TransactionChain

  import Mox

  test "resolve_last_address/1 should retrieve the last address for a chain" do
    Batcher.start_link()

    MockClient
    |> stub(:send_message, fn _, %GetLastTransactionAddress{}, _ ->
      {:ok, %LastTransactionAddress{address: "@Alice10"}}
    end)

    ChainLookup.register_last_address("@Alice1", "@Alice1")
    ChainLookup.register_last_address("@Alice1", "@Alice10")

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(0),
      available?: true,
      geo_patch: "AAA"
    })

    assert "@Alice10" = TransactionChain.resolve_last_address("@Alice1")
  end
end
