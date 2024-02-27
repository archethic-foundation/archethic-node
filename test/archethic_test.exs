defmodule ArchethicTest do
  use ArchethicCase

  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.Balance
  alias Archethic.P2P.Message.GetBalance
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.P2P.Message.GetTransactionChainLength
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.StartMining
  alias Archethic.P2P.Message.TransactionChainLength
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Message.NewTransaction
  alias Archethic.P2P.Message.ValidationError

  alias Archethic.PubSub

  alias Archethic.SelfRepair

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.VersionedTransactionInput

  import ArchethicCase, only: [setup_before_send_tx: 0]

  import Mox
  import Mock
  setup :set_mox_global

  setup do
    setup_before_send_tx()

    :ok
  end

  describe "should follow sequence of checks when sending Transaction" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {122, 12, 0, 5},
        port: 3000,
        first_public_key: "node2",
        last_public_key: "node2",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      P2P.add_and_connect_node(%Node{
        ip: {122, 12, 0, 5},
        port: 3000,
        first_public_key: "node3",
        last_public_key: "node3",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      :ok
    end

    test "should forward Transaction, Current Node Unauthorized and Available" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: false,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      MockClient
      |> expect(:send_message, 1, fn
        _, %NewTransaction{}, _ ->
          {:ok, %Ok{}}
      end)

      assert :ok = Archethic.send_new_transaction(tx, forward?: true)
      Process.sleep(10)
    end

    test "should not forward Transaction" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: false,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      MockClient
      |> expect(:send_message, 0, fn
        _, %NewTransaction{}, _ ->
          {:ok, %Ok{}}
      end)

      assert :ok = Archethic.send_new_transaction(tx, forward?: false)
      Process.sleep(10)
    end

    test "should send StartMining Message, Current Node Synchronized and Available" do
      nss_genesis_address = "nss_genesis_address"
      nss_last_address = "nss_last_address"
      :persistent_term.put(:node_shared_secrets_gen_addr, nss_genesis_address)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-20_000)
      })

      start_supervised!({SummaryTimer, Application.get_env(:archethic, SummaryTimer)})

      now = DateTime.utc_now()

      MockDB
      |> stub(:get_last_chain_address, fn ^nss_genesis_address ->
        {nss_last_address, now}
      end)
      |> stub(
        :get_transaction,
        fn
          ^nss_last_address, [validation_stamp: [:timestamp]], :chain ->
            {:ok,
             %Transaction{
               validation_stamp: %ValidationStamp{
                 timestamp: SharedSecrets.get_last_scheduling_date(now)
               }
             }}

          _, _, _ ->
            {:error, :transaction_not_exists}
        end
      )

      MockClient
      |> expect(:send_message, 3, fn
        _, %StartMining{}, _ ->
          {:ok, %Ok{}}
      end)

      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
      assert :ok = Archethic.send_new_transaction(tx)
    end

    test "should send validation error to welcome node if transaction already locked" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-20_000)
      })

      welcome_node_key = ArchethicCase.random_public_key()

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: welcome_node_key,
        last_public_key: welcome_node_key,
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-20_000)
      })

      MockClient
      |> expect(:send_message, 3, fn
        _, %StartMining{}, _ ->
          {:ok, %Error{reason: :already_locked}}
      end)
      |> expect(
        :send_message,
        fn %Node{first_public_key: ^welcome_node_key}, %ValidationError{}, _ ->
          {:ok, %Ok{}}
        end
      )

      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
      assert :ok = Archethic.send_new_transaction(tx, welcome_node_key: welcome_node_key)
    end

    test "should forward Transaction & Start Repair, Current Node Not Synchronized" do
      nss_genesis_address = "nss_genesis_address"
      nss_last_address = "nss_last_address"
      :persistent_term.put(:node_shared_secrets_gen_addr, nss_genesis_address)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-20_000)
      })

      start_supervised!({SummaryTimer, Application.get_env(:archethic, SummaryTimer)})

      MockDB
      |> stub(:get_last_chain_address, fn ^nss_genesis_address ->
        {nss_last_address, DateTime.utc_now() |> DateTime.add(-20_000)}
      end)
      |> stub(
        :get_transaction,
        fn
          ^nss_last_address, [validation_stamp: [:timestamp]], :chain ->
            {:ok,
             %Transaction{
               validation_stamp: %ValidationStamp{
                 timestamp: DateTime.utc_now() |> DateTime.add(-86_400)
               }
             }}

          _, _, _ ->
            {:error, :transaction_not_exists}
        end
      )

      me = self()

      MockClient
      |> stub(:send_message, fn
        # validate nss chain from network
        # anticippated to be failed
        _, %GetLastTransactionAddress{}, _ ->
          {:ok,
           %LastTransactionAddress{address: "willnotmatchaddress", timestamp: DateTime.utc_now()}}

        _, %NewTransaction{transaction: _, welcome_node: _}, _ ->
          # forward the tx
          send(me, :new_transaction)
          {:ok, %Ok{}}
      end)

      with_mock(SelfRepair, resync: fn _, _, _ -> :ok end) do
        # trying to ssend a tx when NSS chain not synced
        tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
        assert :ok = Archethic.send_new_transaction(tx, forward?: true)

        assert_called(SelfRepair.resync(:_, :_, :_))

        assert_receive :new_transaction, 100
      end
    end

    test "Should forward Transaction until StartMining message is sent without Node Loop & Message Waiting" do
      nss_genesis_address = "nss_genesis_address"
      nss_last_address = "nss_last_address"
      :persistent_term.put(:node_shared_secrets_gen_addr, nss_genesis_address)

      welcome_node = Crypto.first_node_public_key()
      second_node_first_public_key = "node2"

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-20_000)
      })

      start_supervised!({SummaryTimer, Application.get_env(:archethic, SummaryTimer)})

      MockDB
      |> stub(:get_last_chain_address, fn ^nss_genesis_address ->
        {nss_last_address, DateTime.utc_now() |> DateTime.add(-20_000)}
      end)
      |> stub(
        :get_transaction,
        fn
          ^nss_last_address, [validation_stamp: [:timestamp]], :chain ->
            {:ok,
             %Transaction{
               validation_stamp: %ValidationStamp{
                 timestamp: DateTime.utc_now() |> DateTime.add(-86_400)
               }
             }}

          _, _, _ ->
            {:error, :transaction_not_exists}
        end
      )

      me = self()

      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      MockClient
      |> expect(:send_message, 4, fn
        _, %GetLastTransactionAddress{}, _ ->
          {:ok,
           %LastTransactionAddress{address: "willnotmatchaddress", timestamp: DateTime.utc_now()}}

        %Node{first_public_key: ^second_node_first_public_key},
        %NewTransaction{transaction: ^tx, welcome_node: ^welcome_node},
        _ ->
          send(me, {:forwarded_to_node2, tx})
          {:ok, %Ok{}}

        _, %GetTransaction{address: _}, _ ->
          {:ok, %NotFound{}}

        _, %StartMining{transaction: ^tx, welcome_node_public_key: ^welcome_node}, _ ->
          # we are not handling CONSENSUS DFW order in prelimeinay checks for send transaction
          # we rely completely on DFW to handle it.
          {:ok, %Ok{}}
      end)

      # trying to ssend a tx when NSS chain not synced
      with_mock(SelfRepair, resync: fn _, _, _ -> :ok end) do
        assert :ok = Archethic.send_new_transaction(tx, forward?: true)
        assert_receive {:forwarded_to_node2, ^tx}, 100
        assert_called(SelfRepair.resync(:_, :_, :_))
      end
    end
  end

  describe "search_transaction/1" do
    test "should request storage nodes and return the transaction" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

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
      |> expect(:send_message, fn _, %GetTransaction{}, _ ->
        {:ok, %Transaction{address: "@Alice2"}}
      end)

      assert {:ok, %Transaction{address: "@Alice2"}} = Archethic.search_transaction("@Alice2")
    end

    test "should request storage nodes and return not exists as the transaction not exists" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

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
      |> expect(:send_message, fn _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}
      end)

      assert {:error, :transaction_not_exists} = Archethic.search_transaction("@Alice2")
    end
  end

  describe "send_new_transaction/1" do
    test "should elect validation nodes and broadcast the transaction" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      MockClient
      |> expect(:send_message, fn _, %StartMining{}, _ ->
        Process.sleep(20)
        PubSub.notify_new_transaction(tx.address)
        {:ok, %Ok{}}
      end)

      assert :ok = Archethic.send_new_transaction(tx)
    end
  end

  describe "get_last_transaction/1" do
    test "should request storages nodes to fetch the last transaction" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address, timestamp: DateTime.utc_now()}}

        _, %GetTransaction{}, _ ->
          {:ok, %Transaction{previous_public_key: "Alice1"}}
      end)

      assert {:ok, %Transaction{previous_public_key: "Alice1"}} =
               Archethic.get_last_transaction(Crypto.hash("Alice1"))
    end

    test "should request storages nodes to fetch the last transaction but not exists" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address, timestamp: DateTime.utc_now()}}

        _, %GetTransaction{}, _ ->
          {:ok, %NotFound{}}
      end)

      assert {:error, :transaction_not_exists} =
               Archethic.get_last_transaction(Crypto.hash("Alice1"))
    end
  end

  describe "get_balance/1" do
    test "should request storage nodes to fetch the balance" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

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

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key2",
        last_public_key: "key2",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> expect(:send_message, 1, fn
        _, %GetBalance{}, _ ->
          {:ok,
           %Balance{
             uco: 1_000_000_000,
             token: %{
               {"ETH", 1} => 1
             }
           }}
      end)
      |> expect(:send_message, 1, fn
        _, %GetBalance{}, _ ->
          {:ok,
           %Balance{
             uco: 2_000_000_000,
             token: %{
               {"BTC", 2} => 1,
               {"ETH", 1} => 2
             }
           }}
      end)

      assert {:ok,
              %{
                uco: 2_000_000_000,
                token: %{
                  {"ETH", 1} => 2,
                  {"BTC", 2} => 1
                }
              }} = Archethic.get_balance("@Alice2")
    end
  end

  describe "get_transaction_inputs/1" do
    test "should request the storages nodes to fetch the inputs remotely" do
      address1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

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
      |> stub(:send_message, fn
        _, %GetTransactionInputs{address: ^address1}, _ ->
          {:ok,
           %TransactionInputList{
             inputs: [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "@Bob3",
                   amount: 1_000_000_000,
                   spent?: false,
                   type: :UCO,
                   timestamp: DateTime.utc_now()
                 },
                 protocol_version: 1
               }
             ]
           }}
      end)

      assert [%TransactionInput{from: "@Bob3", amount: 1_000_000_000, spent?: false, type: :UCO}] =
               Archethic.get_transaction_inputs(address1)
    end
  end

  describe "get_transaction_chain_length/1" do
    test "should request the storage node to fetch the transaction chain length" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

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
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: "@Alice2"}}

        _, %GetTransactionChainLength{}, _ ->
          {:ok, %TransactionChainLength{length: 3}}
      end)

      assert {:ok, 3} == Archethic.get_transaction_chain_length("@Alice2")
    end
  end
end
