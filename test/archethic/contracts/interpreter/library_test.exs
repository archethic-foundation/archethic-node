defmodule Archethic.Contracts.Interpreter.LibraryTest do
  use ArchethicCase

  alias Archethic.{Contracts.Interpreter.Library, P2P, P2P.Node}

  alias P2P.Message.{
    GetFirstTransactionAddress,
    FirstTransactionAddress
  }

  doctest Library

  import Mox

  test "get_first_transaction_address/1" do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key1",
      last_public_key: "key1",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    MockClient
    |> expect(:send_message, fn
      _, %GetFirstTransactionAddress{address: "addr2"}, _ ->
        {:ok, %FirstTransactionAddress{address: "addr1"}}
    end)

    assert "addr1" == Library.get_first_transaction_address("addr2") |> Library.decode_binary()
  end
end
