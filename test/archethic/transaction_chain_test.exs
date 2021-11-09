defmodule ArchEthic.TransactionChainTest do
  use ArchEthicCase

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetLastTransactionAddress
  alias ArchEthic.P2P.Message.LastTransactionAddress
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData

  doctest TransactionChain

  import Mox

  test "resolve_last_address/1 should retrieve the last address for a chain" do
    MockClient
    |> stub(:send_message, fn
      _, %GetLastTransactionAddress{timestamp: ~U[2021-03-25 15:11:29Z]}, _ ->
        {:ok, %LastTransactionAddress{address: "@Alice1"}}

      _, %GetLastTransactionAddress{timestamp: ~U[2021-03-25 15:12:29Z]}, _ ->
        {:ok, %LastTransactionAddress{address: "@Alice2"}}
    end)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
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
