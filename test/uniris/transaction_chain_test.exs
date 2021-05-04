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
    MockClient
    |> stub(:send_message, fn
      _, %GetLastTransactionAddress{timestamp: ~U[2021-03-25 15:11:29Z]} ->
        {:ok, %LastTransactionAddress{address: "@Alice1"}}

      _, %GetLastTransactionAddress{timestamp: ~U[2021-03-25 15:12:29Z]} ->
        {:ok, %LastTransactionAddress{address: "@Alice2"}}
    end)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
      last_public_key: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    assert "@Alice1" = TransactionChain.resolve_last_address("@Alice1", ~U[2021-03-25 15:11:29Z])
    assert "@Alice2" = TransactionChain.resolve_last_address("@Alice1", ~U[2021-03-25 15:12:29Z])
  end
end
