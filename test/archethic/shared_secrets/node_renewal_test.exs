defmodule ArchEthic.SharedSecrets.NodeRenewalTest do
  use ArchEthicCase

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.SharedSecrets
  alias ArchEthic.SharedSecrets.NodeRenewal

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ownership

  alias ArchEthic.SharedSecrets.NodeRenewal

  import Mox

  test "new_node_shared_secrets_transaction/3 should create a new node shared secrets transaction" do
    aes_key = :crypto.strong_rand_bytes(32)

    %Transaction{
      type: :node_shared_secrets,
      data: %TransactionData{
        ownerships: [ownership = %Ownership{}],
        content: content
      }
    } =
      SharedSecrets.new_node_shared_secrets_transaction(
        [Crypto.last_node_public_key()],
        "daily_nonce_seed",
        aes_key
      )

    assert Ownership.authorized_public_key?(ownership, Crypto.last_node_public_key())

    assert {:ok, _, _} = NodeRenewal.decode_transaction_content(content)
  end

  describe "initiator?/0" do
    test "should return false when the first elected node is not the current node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: Crypto.last_node_public_key(),
        first_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: false
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key2",
        first_public_key: "key2",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-86_400)
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key3",
        first_public_key: "key3",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-86_400)
      })

      assert false == NodeRenewal.initiator?()
    end

    test "should return true when the first elected node is the current node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: Crypto.last_node_public_key(),
        first_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-86_400)
      })

      assert true == NodeRenewal.initiator?()
    end
  end

  describe "next_authorized_node_public_keys/0" do
    test "should not add new nodes with a low tps" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key1",
        first_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key2",
        first_public_key: "key2",
        network_patch: "DEF",
        geo_patch: "DEF",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key3",
        first_public_key: "key3",
        network_patch: "FA1",
        geo_patch: "FA1",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key4",
        first_public_key: "key4",
        network_patch: "321",
        geo_patch: "321",
        available?: true,
        authorization_date: DateTime.utc_now()
      })

      MockDB
      |> expect(:get_latest_tps, fn -> 10.0 end)

      assert Enum.all?(
               NodeRenewal.next_authorized_node_public_keys(),
               &(&1 in ["key2", "key1", "key3"])
             )
    end

    test "should add new nodes with a high tps" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key1",
        first_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key2",
        first_public_key: "key2",
        network_patch: "DEF",
        geo_patch: "DEF",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key3",
        first_public_key: "key3",
        network_patch: "FA1",
        geo_patch: "FA1",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key4",
        first_public_key: "key4",
        network_patch: "321",
        geo_patch: "321",
        available?: true,
        authorization_date: DateTime.utc_now()
      })

      MockDB
      |> expect(:get_latest_tps, fn -> 1000.0 end)

      assert Enum.all?(
               NodeRenewal.next_authorized_node_public_keys(),
               &(&1 in ["key2", "key1", "key3", "key4"])
             )
    end
  end
end
