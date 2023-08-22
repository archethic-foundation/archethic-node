defmodule Archethic.ReplicationTest do
  use ArchethicCase, async: false

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Mining.Fee

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.GetTransactionChainLength
  alias Archethic.P2P.Message.TransactionChainLength
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.NotifyLastTransactionAddress
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetGenesisAddress
  # alias Archethic.P2P.Message.GenesisAddress

  alias Archethic.Replication

  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.MemTables.NetworkLookup

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  doctest Archethic.Replication

  import Mox

  setup do
    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    :ok
  end

  test "validate_transaction" do
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

    unspent_outputs = [
      %UnspentOutput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }
    ]

    p2p_context()
    tx = create_valid_transaction(unspent_outputs)

    MockClient
    |> stub(:send_message, fn
      _, %GetTransactionInputs{}, _ ->
        {:ok,
         %TransactionInputList{
           inputs:
             Enum.map(unspent_outputs, fn utxo ->
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: utxo.from,
                   amount: utxo.amount,
                   type: utxo.type,
                   timestamp:
                     DateTime.utc_now() |> DateTime.add(-30) |> DateTime.truncate(:millisecond)
                 },
                 protocol_version: 1
               }
             end)
         }}

      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}

      _, %GetTransactionChainLength{}, _ ->
        %TransactionChainLength{length: 1}

      _, %GetGenesisAddress{}, _ ->
        {:ok, %NotFound{}}
    end)

    assert :ok = Replication.validate_transaction(tx)
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

    unspent_outputs = [
      %UnspentOutput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }
    ]

    p2p_context()
    tx = create_valid_transaction(unspent_outputs)

    MockDB
    |> expect(:write_transaction, fn ^tx, _ ->
      send(me, :replicated)
      :ok
    end)

    MockClient
    |> stub(:send_message, fn
      _, %GetTransactionInputs{}, _ ->
        {:ok,
         %TransactionInputList{
           inputs:
             Enum.map(unspent_outputs, fn utxo ->
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: utxo.from,
                   amount: utxo.amount,
                   type: utxo.type,
                   timestamp:
                     DateTime.utc_now() |> DateTime.add(-30) |> DateTime.truncate(:millisecond)
                 },
                 protocol_version: 1
               }
             end)
         }}

      _, %GetTransactionChain{}, _ ->
        Process.sleep(10)
        {:ok, %TransactionList{transactions: []}}

      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}

      _, %GetTransactionChainLength{}, _ ->
        %TransactionChainLength{length: 1}

      _, %GetGenesisAddress{}, _ ->
        {:ok, %NotFound{}}
    end)

    assert :ok = Replication.validate_and_store_transaction_chain(tx)
    assert_receive :replicated
  end

  test "validate_and_store_transaction/1" do
    me = self()

    unspent_outputs = [
      %UnspentOutput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }
    ]

    p2p_context()
    tx = create_valid_transaction(unspent_outputs)

    MockDB
    |> expect(:write_transaction, fn _, _ ->
      send(me, :replicated)
      :ok
    end)

    assert :ok = Replication.validate_and_store_transaction(tx)

    Process.sleep(200)

    assert_receive :replicated
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
      authorization_date: DateTime.add(DateTime.utc_now(), -1),
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.add(DateTime.utc_now(), -1),
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
        authorization_date: DateTime.add(DateTime.utc_now(), -1),
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
    timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    ledger_operations =
      %LedgerOperations{
        fee: Fee.calculate(tx, 0.07, timestamp)
      }
      |> LedgerOperations.consume_inputs(tx.address, unspent_outputs, timestamp)
      |> elem(1)

    validation_stamp =
      %ValidationStamp{
        timestamp: timestamp,
        proof_of_work: Crypto.origin_node_public_key(),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        ledger_operations: ledger_operations,
        protocol_version: ArchethicCase.current_protocol_version()
      }
      |> ValidationStamp.sign()

    cross_validation_stamp = CrossValidationStamp.sign(%CrossValidationStamp{}, validation_stamp)

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  describe "acknowledge_previous_storage_nodes/1" do
    test "should notify last transaction address for the previous storage nodes" do
      me = self()

      Enum.each(0..50, fn i ->
        P2P.add_and_connect_node(%Node{
          first_public_key: "key-#{i}",
          last_public_key: "key-#{i}",
          geo_patch: "#{Integer.to_string(i, 16)}A",
          available?: true,
          authorized?: true,
          authorization_date: DateTime.utc_now()
        })
      end)

      previous_public_key = "previous_public_key"

      MockDB
      |> expect(:get_genesis_address, fn _ -> "@Alice0" end)
      |> expect(:get_transaction, fn _, _, _ ->
        {:ok,
         %Transaction{
           validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()},
           previous_public_key: previous_public_key
         }}
      end)
      |> expect(:list_chain_addresses, fn _ -> [{"@Alice1", DateTime.utc_now()}] end)

      MockClient
      |> stub(:send_message, fn _,
                                %NotifyLastTransactionAddress{
                                  last_address: last_address,
                                  genesis_address: genesis_address,
                                  previous_address: previous_address
                                },
                                _ ->
        send(me, {:last_address, last_address, genesis_address, previous_address})
        {:ok, %Ok{}}
      end)

      derived_previous_address = Crypto.derive_address(previous_public_key)

      assert :ok = Replication.acknowledge_previous_storage_nodes("@Alice2")

      assert_receive {:last_address, "@Alice2", "@Alice0", ^derived_previous_address}
    end

    test "should process NotifyLastTransactionAddress message with TransactionChain.register_last_address if last address is different than the previous address" do
      previous_public_key = "previous_public_key"

      MockDB
      |> expect(:get_genesis_address, fn _ -> "@Alice0" end)
      |> expect(:get_transaction, fn _, _, _ ->
        {:ok,
         %Transaction{
           validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()},
           previous_public_key: previous_public_key
         }}
      end)
      |> expect(:list_chain_addresses, fn _ -> [{"@Alice1", DateTime.utc_now()}] end)
      |> expect(:add_last_transaction_address, 0, fn _, _, _ -> :ok end)

      MockClient
      |> stub(:send_message, fn _, msg = %NotifyLastTransactionAddress{}, _ ->
        Message.process(msg, "key")
        {:ok, %Ok{}}
      end)

      assert :ok = Replication.acknowledge_previous_storage_nodes("@Alice2")
    end
  end
end
