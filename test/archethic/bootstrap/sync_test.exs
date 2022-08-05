defmodule Archethic.Bootstrap.SyncTest do
  use ArchethicCase, async: false

  alias Archethic.Account

  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer

  alias Archethic.Bootstrap.Sync

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransactionChainLength
  alias Archethic.P2P.Message.TransactionChainLength
  alias Archethic.P2P.Message.EncryptedStorageNonce
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.GetStorageNonce
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.ListNodes
  alias Archethic.P2P.Message.NodeList
  alias Archethic.P2P.Message.NotifyEndOfNodeSync
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Node

  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.NodeRenewalScheduler

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Reward.MemTables.RewardTokens, as: RewardMemTable
  alias Archethic.Reward.MemTablesLoader, as: RewardTableLoader

  doctest Sync

  @moduletag :capture_log

  import Mox

  setup do
    MockClient
    |> stub(:send_message, fn
      _, %GetLastTransactionAddress{address: address}, _ ->
        {:ok, %LastTransactionAddress{address: address}}

      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}

      _, %GetTransactionInputs{}, _ ->
        {:ok, %TransactionInputList{inputs: []}}

      _, %GetTransactionChain{}, _ ->
        {:ok, %TransactionList{transactions: []}}

      _, %GetTransactionChainLength{}, _ ->
        %TransactionChainLength{length: 1}
    end)

    MockDB
    |> stub(:list_transactions_by_type, fn :mint_rewards, [:address, :type] ->
      [
        %Transaction{
          address: "@RewardToken0",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken1",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken2",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken3",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken4",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        }
      ]
    end)

    start_supervised!(RewardMemTable)
    start_supervised!(RewardTableLoader)

    :ok
  end

  describe "should_initialize_network?/1" do
    test "should return true when the network has not been deployed and it's the first bootstrapping seed" do
      assert true == Sync.should_initialize_network?([])
    end

    test "should return false when the network has been initialized" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})

      stamp = %ValidationStamp{
        timestamp: DateTime.utc_now(),
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

  describe "require_update?/4" do
    test "should return false when only a node is involved in the network" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        transport: :tcp
      })

      assert false ==
               Sync.require_update?({193, 101, 10, 202}, 3000, 4000, :tcp, DateTime.utc_now())
    end

    test "should return true when the node ip change" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        transport: :tcp
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        http_port: 4000,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key",
        transport: :tcp
      })

      assert Sync.require_update?({193, 101, 10, 202}, 3000, 4000, :tcp, DateTime.utc_now())
    end

    test "should return true when the node port change" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        transport: :tcp
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        http_port: 4000,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key",
        transport: :tcp
      })

      assert Sync.require_update?({127, 0, 0, 1}, 3010, 4000, :tcp, DateTime.utc_now())
    end

    test "should return true when the last date of sync diff is greater than 3 seconds" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        transport: :tcp
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        http_port: 4000,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key",
        transport: :tcp
      })

      assert Sync.require_update?(
               {127, 0, 0, 1},
               3000,
               4000,
               :tcp,
               DateTime.utc_now()
               |> DateTime.add(-10)
             )
    end

    test "should return true when the transport change" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        transport: :tcp
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        http_port: 4000,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key",
        transport: :tcp
      })

      assert true ==
               Sync.require_update?({193, 101, 10, 202}, 3000, 4000, :sctp, DateTime.utc_now())
    end
  end

  describe "initialize_network/2" do
    setup do
      start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
      start_supervised!({NodeRenewalScheduler, interval: "0 * * * * *"})

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        transport: MockTransport,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      :ok
    end

    test "should initiate storage nonce, first node transaction, node shared secrets and genesis wallets" do
      start_supervised!({Archethic.SelfRepair.Scheduler, [interval: "0 0 0 * *"]})

      MockDB
      |> stub(:chain_size, fn _ -> 1 end)

      {:ok, daily_nonce_agent} = Agent.start_link(fn -> %{} end)

      MockCrypto
      |> stub(:unwrap_secrets, fn encrypted_secrets, encrypted_secret_key, timestamp ->
        <<enc_daily_nonce_seed::binary-size(60), _enc_transaction_seed::binary-size(60),
          _enc_network_pool_seed::binary-size(60)>> = encrypted_secrets

        {:ok, aes_key} = Crypto.ec_decrypt_with_first_node_key(encrypted_secret_key)
        {:ok, daily_nonce_seed} = Crypto.aes_decrypt(enc_daily_nonce_seed, aes_key)
        daily_nonce_keypair = Crypto.generate_deterministic_keypair(daily_nonce_seed)

        Agent.update(daily_nonce_agent, fn state ->
          Map.put(state, timestamp, daily_nonce_keypair)
        end)
      end)
      |> stub(:sign_with_daily_nonce_key, fn data, timestamp ->
        {_pub, pv} =
          Agent.get(daily_nonce_agent, fn state ->
            state
            |> Enum.sort_by(&elem(&1, 0), {:desc, DateTime})
            |> Enum.filter(&(DateTime.diff(elem(&1, 0), timestamp) <= 0))
            |> List.first()
            |> elem(1)
          end)

        Crypto.sign(data, pv)
      end)

      node_tx =
        Transaction.new(:node, %TransactionData{
          content:
            Node.encode_transaction_content(
              {127, 0, 0, 1},
              3000,
              4000,
              :tcp,
              <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
              <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
              :crypto.strong_rand_bytes(64)
            )
        })

      :ok = Sync.initialize_network(node_tx)

      assert %Node{authorized?: true} = P2P.get_node_info()
      assert 1 == Crypto.number_of_node_shared_secrets_keys()

      assert 2 == SharedSecrets.list_origin_public_keys() |> Enum.count()

      Application.get_env(:archethic, Archethic.Bootstrap.NetworkInit)[:genesis_pools]
      |> Enum.each(fn %{address: address, amount: amount} ->
        assert %{uco: amount, token: %{}} == Account.get_balance(address)
      end)
    end
  end

  test "load_node_list/1 should request node list from the closest nodes" do
    node = %Node{
      ip: {80, 10, 101, 202},
      port: 4390,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key1"
    }

    :ok = P2P.add_and_connect_node(node)

    MockClient
    |> stub(:send_message, fn
      _, %ListNodes{}, _ ->
        {:ok,
         %NodeList{
           nodes: [
             %Node{
               ip: {127, 0, 0, 1},
               port: 3000,
               http_port: 4000,
               first_public_key: "key2",
               last_public_key: "key2"
             }
           ]
         }}
    end)

    assert :ok = Sync.load_node_list([node])

    assert [
             node,
             %Node{
               ip: {127, 0, 0, 1},
               port: 3000,
               http_port: 4000,
               first_public_key: "key2",
               last_public_key: "key2"
             }
           ] == P2P.list_nodes()
  end

  test "load_storage_nonce/1 should fetch the storage nonce, decrypt it with the node key" do
    node = %Node{
      ip: {80, 10, 101, 202},
      port: 4390,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key1"
    }

    :ok = P2P.add_and_connect_node(node)

    me = self()

    MockClient
    |> expect(:send_message, fn _, %GetStorageNonce{public_key: public_key}, _ ->
      encrypted_nonce = Crypto.ec_encrypt("fake_storage_nonce", public_key)
      {:ok, %EncryptedStorageNonce{digest: encrypted_nonce}}
    end)

    MockCrypto
    |> stub(:set_storage_nonce, fn nonce ->
      send(me, {:nonce, nonce})
      :ok
    end)

    assert :ok = Sync.load_storage_nonce([node])
    assert_receive {:nonce, "fake_storage_nonce"}
  end

  test "publish_end_of_sync/0 should notify the network the node have finished its synchronization" do
    BeaconSlotTimer.start_link([interval: "0 * * * * *"], [])

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      available?: true,
      geo_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    me = self()

    MockClient
    |> stub(:send_message, fn _, %NotifyEndOfNodeSync{}, _ ->
      send(me, :end_of_sync)
      {:ok, %Ok{}}
    end)

    assert :ok = Sync.publish_end_of_sync()
    assert_receive :end_of_sync
  end
end
