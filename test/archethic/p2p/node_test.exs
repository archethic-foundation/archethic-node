defmodule Archethic.P2P.NodeTest do
  use ExUnit.Case

  alias Archethic.P2P.Node
  alias Archethic.P2P.NodeConfig

  import ArchethicCase

  doctest Node

  test "serialize/deserialize node" do
    node = %Node{
      first_public_key: random_public_key(),
      last_public_key: random_public_key(),
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
      reward_address: random_address(),
      last_address: random_address(),
      origin_public_key: random_public_key(),
      mining_public_key: random_public_key()
    }

    assert {node, <<>>} == node |> Node.serialize() |> Node.deserialize()
  end

  describe "encode/decode " do
    test "should encode & decode node transaction content" do
      node_config = %NodeConfig{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        transport: :tcp,
        reward_address: random_address(),
        origin_public_key: random_public_key(),
        origin_certificate: :crypto.strong_rand_bytes(64),
        mining_public_key: <<3::8, 2::8, :crypto.strong_rand_bytes(48)::binary>>,
        geo_patch: "AAA"
      }

      assert {:ok, node_config} ==
               node_config
               |> Node.encode_transaction_content()
               |> Node.decode_transaction_content()
    end
  end
end
