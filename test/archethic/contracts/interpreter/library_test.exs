defmodule ArchEthic.Contracts.Interpreter.LibraryTest do
  use ArchEthicCase

  alias ArchEthic.Contracts.Interpreter.Library
  alias ArchEthic.Crypto
  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Message.FirstPublicKey

  doctest Library

  import Mox

  describe "get_genesis_address/1" do
    setup do
      key = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: key,
        last_public_key: key,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      {:ok, [key: key]}
    end

    test "with empty node list" do
      MockClient
      |> expect(:send_message, fn _, _, _ -> {:error, :network_issue} end)

      address = :crypto.strong_rand_bytes(34) |> Base.encode16()
      assert {:error, :network_issue} == Library.get_genesis_address(address)
    end

    test "with NotFound node list" do
      MockClient
      |> expect(:send_message, fn _, _, _ -> {:ok, %NotFound{}} end)

      address = :crypto.strong_rand_bytes(34) |> Base.encode16()
      assert {:error, :network_issue} == Library.get_genesis_address(address)
    end

    test "with FirstPublicKey returned", %{key: key} do
      genesis_address = Crypto.derive_address(key)

      MockClient
      |> expect(:send_message, fn _, _, _ -> {:ok, %FirstPublicKey{public_key: key}} end)

      address = :crypto.strong_rand_bytes(34) |> Base.encode16()
      assert genesis_address == Library.get_genesis_address(address)
    end
  end
end
