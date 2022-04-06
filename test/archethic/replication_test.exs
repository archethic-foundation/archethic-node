defmodule ArchEthic.ReplicationTest do
  use ArchEthicCase, async: false

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.Mining.Fee

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.NotifyLastTransactionAddress
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.P2P.Node

  alias ArchEthic.Replication

  alias ArchEthic.SharedSecrets
  alias ArchEthic.SharedSecrets.MemTables.NetworkLookup

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.CrossValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionData

  doctest ArchEthic.Replication

  import Mox

  setup do
    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    :ok
  end

  test "validate_and_store_transaction_chain/2" do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      authorized?: true,
      last_public_key: Crypto.last_node_public_key(),
      first_public_key: Crypto.last_node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now(),
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    me = self()

    unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 1_000_000_000, type: :UCO}]
    p2p_context()
    tx = create_valid_transaction(unspent_outputs)

    MockDB
    |> expect(:write_transaction, fn ^tx ->
      send(me, :replicated)
      :ok
    end)

    MockClient
    |> stub(:send_message, fn
      _, %GetUnspentOutputs{}, _ ->
        {:ok,
         %UnspentOutputList{
           unspent_outputs: unspent_outputs
         }}

      _, %GetTransactionChain{}, _ ->
        Process.sleep(10)
        {:ok, %TransactionList{transactions: []}}

      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}
    end)

    assert :ok = Replication.validate_and_store_transaction_chain(tx, [])

    Process.sleep(200)

    assert_received :replicated
  end

  test "validate_and_store_transaction/1" do
    me = self()

    unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 1_000_000_000, type: :UCO}]
    p2p_context()
    tx = create_valid_transaction(unspent_outputs)

    MockDB
    |> expect(:write_transaction, fn _ ->
      send(me, :replicated)
      :ok
    end)

    assert :ok = Replication.validate_and_store_transaction(tx)

    Process.sleep(200)

    assert_received :replicated
  end

  defp p2p_context do
    SharedSecrets.add_origin_public_key(:software, Crypto.first_node_public_key())

    welcome_node = %Node{
      first_public_key: "key1",
      last_public_key: "key1",
      available?: true,
      geo_patch: "BBB",
      network_patch: "BBB",
      enrollment_date: DateTime.utc_now(),
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    }

    coordinator_node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now(),
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now(),
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB",
        authorization_date: DateTime.utc_now(),
        reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      }
    ]

    Enum.each(storage_nodes, &P2P.add_and_connect_node(&1))

    P2P.add_and_connect_node(welcome_node)
    P2P.add_and_connect_node(coordinator_node)

    %{
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      storage_nodes: storage_nodes
    }
  end

  defp create_valid_transaction(unspent_outputs) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        fee: Fee.calculate(tx, 0.07)
      }
      |> LedgerOperations.consume_inputs(tx.address, unspent_outputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.first_node_public_key(),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        ledger_operations: ledger_operations
      }
      |> ValidationStamp.sign()

    cross_validation_stamp = CrossValidationStamp.sign(%CrossValidationStamp{}, validation_stamp)

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  describe "acknowledge_previous_storage_nodes/2" do
    test "should register new address on chain" do
      MockDB
      |> stub(:add_last_transaction_address, fn _address, _last_address, _ ->
        :ok
      end)
      |> expect(:get_last_chain_address, fn _ -> "@Alice2" end)

      assert :ok =
               Replication.acknowledge_previous_storage_nodes(
                 "@Alice2",
                 "@Alice1",
                 DateTime.utc_now()
               )

      assert "@Alice2" == TransactionChain.get_last_address("@Alice1")
    end

    test "should notify previous storage pool if transaction exists" do
      MockDB
      |> stub(:add_last_transaction_address, fn _address, _last_address, _ ->
        :ok
      end)
      |> expect(:get_last_chain_address, fn _ -> "@Alice2" end)
      |> stub(:get_transaction, fn _, _ ->
        {:ok, %Transaction{previous_public_key: "Alice1"}}
      end)

      me = self()

      MockClient
      |> stub(:send_message, fn _, %NotifyLastTransactionAddress{address: _}, _ ->
        send(me, :notification_sent)
        {:ok, %Ok{}}
      end)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: "AAA",
        available?: true,
        authorization_date: DateTime.utc_now(),
        authorized?: true,
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      })

      assert :ok =
               Replication.acknowledge_previous_storage_nodes(
                 "@Alice2",
                 "@Alice1",
                 DateTime.utc_now()
               )

      assert "@Alice2" == TransactionChain.get_last_address("@Alice1")

      assert_receive :notification_sent, 500
    end
  end
end
