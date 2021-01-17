defmodule Uniris.TransactionChainTest do
  use UnirisCase

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetLastTransactionAddress
  alias Uniris.P2P.Message.LastTransactionAddress
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  doctest TransactionChain

  import Mox

  test "resolve_last_address/1 should retrieve the last address for a chain" do
    MockTransport
    |> stub(:send_message, fn _, _, %GetLastTransactionAddress{} ->
      {:ok, %LastTransactionAddress{address: "@Alice10"}}
    end)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      available?: true,
      geo_patch: "AAA"
    })

    assert "@Alice10" = TransactionChain.resolve_last_address("@Alice1")
  end
end
