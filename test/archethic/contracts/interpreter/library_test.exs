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

    addr1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::bitstring>>
    addr2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::bitstring>>

    MockClient
    |> expect(:send_message, fn
      _, %GetFirstTransactionAddress{address: ^addr1}, _ ->
        {:ok, %FirstTransactionAddress{address: addr2}}
    end)

    assert Base.encode16(addr2) == Library.get_first_transaction_address(Base.encode16(addr1))
  end
end
