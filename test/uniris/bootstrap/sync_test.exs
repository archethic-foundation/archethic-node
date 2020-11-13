defmodule Uniris.Bootstrap.SyncTest do
  use UnirisCase, async: false

  alias Uniris.Account

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.BeaconChain.Subset, as: BeaconSubset

  alias Uniris.Bootstrap.Sync

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.EncryptedStorageNonce
  alias Uniris.P2P.Message.GetStorageNonce
  alias Uniris.P2P.Message.ListNodes
  alias Uniris.P2P.Message.NodeList
  alias Uniris.P2P.Node

  alias Uniris.SharedSecrets.NodeRenewalScheduler

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.TransactionData

  doctest Sync

  @moduletag :capture_log

  import Mox

  describe "should_initialize_network?/1" do
    test "should return true when the network has not been deployed and it's the first bootstrapping seed" do
      assert true == Sync.should_initialize_network?([])
    end

    test "should return false when the network has been initialized" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})

      stamp = %ValidationStamp{
        proof_of_work: "",
        proof_of_integrity: "",
        ledger_operations: %LedgerOperations{},
        signature: ""
      }

      cross_stamp = %CrossValidationStamp{}

      :ok =
        TransactionChain.write_transaction(%{
          tx
          | validation_stamp: stamp,
            cross_validation_stamps: [cross_stamp]
        })

      assert false ==
               Sync.should_initialize_network?([
                 %Node{first_public_key: "key1"},
                 %Node{first_public_key: "key1"}
               ])
    end
  end

  describe "require_update?/3" do
    test "should return false when only a node is involved in the network" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(1)
      })

      assert false == Sync.require_update?({193, 101, 10, 202}, 3000, DateTime.utc_now())
    end

    test "should return true when the node ip change" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(1)
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key"
      })

      assert Sync.require_update?({193, 101, 10, 202}, 3000, DateTime.utc_now())
    end

    test "should return true when the node port change" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(1)
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key"
      })

      assert Sync.require_update?({127, 0, 0, 1}, 3010, DateTime.utc_now())
    end

    test "should return true when the last date of sync diff is greater than 3 seconds" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(1)
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key"
      })

      assert Sync.require_update?(
               {127, 0, 0, 1},
               3000,
               DateTime.utc_now()
               |> DateTime.add(-10)
             )
    end
  end

  describe "initialize_network/2" do
    setup do
      Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))
      start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *", trigger_offset: 0})
      start_supervised!({NodeRenewalScheduler, interval: "0 * * * * *", trigger_offset: 0})

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(1),
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      :ok
    end

    test "should initiate storage nonce, first node transaction, node shared secrets and genesis wallets" do
      Sync.initialize_network({127, 0, 0, 1}, 3000)

      assert :persistent_term.get(:storage_nonce) != nil

      assert 1 = TransactionChain.count_transactions_by_type(:node_shared_secrets)
      assert 1 = Crypto.number_of_node_keys()

      Application.get_env(:uniris, Uniris.Bootstrap.NetworkInit)[:genesis_pools]
      |> Enum.map(fn {_, public_key: key, amount: amount} -> {key, amount} end)
      |> Enum.each(fn {key, amount} ->
        address =
          key
          |> Base.decode16!()
          |> Crypto.hash()

        assert %{uco: amount, nft: %{}} == Account.get_balance(address)
      end)
    end
  end

  test "load_node_list/1 should request node list from the closest nodes" do
    node = %Node{
      ip: {80, 10, 101, 202},
      port: 4390,
      first_public_key: "key1",
      last_public_key: "key1"
    }

    :ok = P2P.add_node(node)

    MockTransport
    |> stub(:send_message, fn
      _, _, %ListNodes{} ->
        {:ok,
         %NodeList{
           nodes: [
             %Node{
               ip: {127, 0, 0, 1},
               port: 3000,
               first_public_key: "key2",
               last_public_key: "key2"
             }
           ]
         }}
    end)

    assert :ok = Sync.load_node_list(node)

    assert [
             node,
             %Node{
               ip: {127, 0, 0, 1},
               port: 3000,
               first_public_key: "key2",
               last_public_key: "key2"
             }
           ] = P2P.list_nodes()
  end

  test "load_storage_nonce/1 should fetch the storage nonce, decrypt it with the node key" do
    node = %Node{
      ip: {80, 10, 101, 202},
      port: 4390,
      first_public_key: "key1",
      last_public_key: "key1"
    }

    :ok = P2P.add_node(node)

    MockTransport
    |> expect(:send_message, fn _, _, %GetStorageNonce{public_key: public_key} ->
      encrypted_nonce = Crypto.ec_encrypt("fake_storage_nonce", public_key)
      {:ok, %EncryptedStorageNonce{digest: encrypted_nonce}}
    end)

    assert :ok = Sync.load_storage_nonce(node)
    assert "fake_storage_nonce" = :persistent_term.get(:storage_nonce)
  end
end
