defmodule Archethic.P2P.NodeTest do
  use ExUnit.Case
  alias alias Archethic.P2P.Node
  doctest Node

  test "serialize/deserialize node" do
    node = %Node{
      first_public_key: ArchethicCase.random_public_key(),
      last_public_key: ArchethicCase.random_public_key(),
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      transport: :tcp,
      geo_patch: "FA9",
      network_patch: "AVC",
      available?: true,
      synced?: true,
      average_availability: 0.8,
      enrollment_date: ~U[2020-06-26 08:36:11Z],
      authorization_date: ~U[2020-06-26 08:36:11Z],
      last_update_date: ~U[2020-06-26 08:36:11Z],
      availability_update: ~U[2020-06-26 08:36:11Z],
      authorized?: true,
      reward_address: ArchethicCase.random_address(),
      last_address: ArchethicCase.random_address(),
      origin_public_key: ArchethicCase.random_public_key(),
      mining_public_key: ArchethicCase.random_public_key()
    }

    assert {^node, _} =
             node
             |> Node.serialize()
             |> Node.deserialize()
  end

  describe "encode/decode " do
    test "should encode & decode node transaction content" do
      reward_address = ArchethicCase.random_address()
      origin_public_key = ArchethicCase.random_public_key()
      certificate = ""
      mining_public_key = ArchethicCase.random_public_key()

      assert {:ok, {127, 0, 0, 1}, 3000, 4000, :tcp, ^reward_address, ^origin_public_key,
              ^certificate,
              ^mining_public_key} =
               Node.encode_transaction_content(
                 {127, 0, 0, 1},
                 3000,
                 4000,
                 :tcp,
                 reward_address,
                 origin_public_key,
                 certificate,
                 mining_public_key
               )
               |> Node.decode_transaction_content()
    end
  end
end
