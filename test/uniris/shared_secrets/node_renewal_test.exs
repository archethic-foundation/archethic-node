defmodule Uniris.SharedSecrets.NodeRenewalTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.SelfRepair.Sync.BeaconSummaryHandler.NetworkStatistics

  alias Uniris.SharedSecrets
  alias Uniris.SharedSecrets.NodeRenewal

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys

  alias Uniris.SharedSecrets.NodeRenewal

  test "new_node_shared_secrets_transaction/3 should create a new node shared secrets transaction" do
    aes_key = :crypto.strong_rand_bytes(32)

    %Transaction{
      type: :node_shared_secrets,
      data: %TransactionData{
        keys: %Keys{
          authorized_keys: authorized_keys,
          secret: _
        },
        content: content
      }
    } =
      SharedSecrets.new_node_shared_secrets_transaction(
        [Crypto.last_node_public_key()],
        "daily_nonce_seed",
        aes_key
      )

    assert Map.has_key?(authorized_keys, Crypto.last_node_public_key())

    assert Regex.match?(
             ~r/daily nonce public_key: ([0-9a-fA-F]{66,130})\nnetwork pool address: ([0-9a-fA-F]{66,130})/m,
             content
           )
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
        authorization_date: DateTime.utc_now()
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
        authorization_date: DateTime.utc_now()
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
        authorization_date: DateTime.utc_now()
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

      NetworkStatistics.register_tps(DateTime.utc_now(), 10.0, 100)

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

      NetworkStatistics.register_tps(DateTime.utc_now(), 1000.0, 500)

      assert Enum.all?(
               NodeRenewal.next_authorized_node_public_keys(),
               &(&1 in ["key2", "key1", "key3", "key4"])
             )
    end
  end
end
