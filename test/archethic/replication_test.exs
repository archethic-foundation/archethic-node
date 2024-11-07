defmodule Archethic.ReplicationTest do
  use ArchethicCase, async: false

  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.ContractFactory
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.State

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.NotifyLastTransactionAddress
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Node

  alias Archethic.Replication
  alias Archethic.Replication.TransactionContext

  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.MemTables.NetworkLookup

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionFactory

  doctest Archethic.Replication

  import Mock
  import Mox
  import ArchethicCase

  setup do
    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    MockDB
    |> stub(:list_transactions, fn _ -> [] end)
    |> stub(:list_io_transactions, fn _ -> [] end)

    :ok
  end

  test "validate_transaction without contract_context" do
    unspent_outputs = [
      %UnspentOutput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }
    ]

    p2p_context()

    tx =
      TransactionFactory.create_valid_transaction(unspent_outputs, type: :data, content: "content")

    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}
    end)

    with_mock(TransactionContext, [:passthrough],
      fetch_transaction_unspent_outputs: fn _ ->
        VersionedUnspentOutput.wrap_unspent_outputs(unspent_outputs, current_protocol_version())
      end
    ) do
      assert %CrossValidationStamp{inconsistencies: []} =
               Replication.validate_transaction(
                 tx,
                 nil,
                 VersionedUnspentOutput.wrap_unspent_outputs(
                   unspent_outputs,
                   current_protocol_version()
                 )
               )

      assert_called(TransactionContext.fetch_transaction_unspent_outputs(:_))
    end
  end

  test "validate_transaction with a state" do
    P2P.add_and_connect_node(new_node())

    unspent_outputs = [
      %UnspentOutput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }
    ]

    v_unspent_outputs =
      VersionedUnspentOutput.wrap_unspent_outputs(unspent_outputs, current_protocol_version())

    now = ~U[2023-01-01 00:00:00Z]

    code = """
    @version 1

    actions triggered_by: datetime, at: #{DateTime.to_unix(now)} do
      State.set("key", "value")
      Contract.set_content "ok"
    end
    """

    p2p_context()

    encoded_state = State.serialize(%{"key" => "value"})

    prev_tx = ContractFactory.create_valid_contract_tx(code)
    previous_address = prev_tx.address

    next_tx =
      ContractFactory.create_next_contract_tx(prev_tx,
        content: "ok",
        state: encoded_state,
        inputs: unspent_outputs
      )

    genesis_address = Transaction.previous_address(prev_tx)

    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{address: ^previous_address}, _ ->
        {:ok, prev_tx}

      _, %GetGenesisAddress{address: ^previous_address}, _ ->
        {:ok, %GenesisAddress{address: genesis_address, timestamp: DateTime.utc_now()}}
    end)

    with_mock(TransactionContext, [:passthrough],
      fetch_transaction_unspent_outputs: fn _ -> v_unspent_outputs end
    ) do
      assert %CrossValidationStamp{inconsistencies: []} =
               Replication.validate_transaction(
                 next_tx,
                 %Contract.Context{
                   status: :tx_output,
                   trigger: {:datetime, now},
                   timestamp: now,
                   inputs: v_unspent_outputs
                 },
                 v_unspent_outputs
               )

      assert_called(TransactionContext.fetch_transaction_unspent_outputs(:_))
    end
  end

  test "validate_and_store_transaction/2" do
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

    tx = TransactionFactory.create_valid_transaction(unspent_outputs)

    MockDB
    |> expect(:write_transaction, fn _, _ ->
      send(me, :replicated)
      :ok
    end)

    assert :ok = Replication.validate_and_store_transaction(tx)

    assert_receive :replicated
  end

  defp p2p_context do
    SharedSecrets.add_origin_public_key(:software, Crypto.first_node_public_key())

    welcome_node =
      new_node(
        first_public_key: "key1",
        last_public_key: "key1",
        mining_public_key: "key1",
        geo_patch: "BBB",
        network_patch: "BBB"
      )

    coordinator_node = new_node()

    storage_nodes = [
      new_node(
        first_public_key: "key3",
        last_public_key: "key3",
        mining_public_key: "key3",
        geo_patch: "BBB",
        network_patch: "BBB"
      )
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

  describe "acknowledge_previous_storage_nodes/1" do
    test "should notify last transaction address for the previous storage nodes" do
      me = self()

      Enum.each(0..50, fn i ->
        P2P.add_and_connect_node(
          new_node(
            first_public_key: "key-#{i}",
            last_public_key: "key-#{i}",
            mining_public_key: "key-#{i}",
            geo_patch: "#{Integer.to_string(i, 16)}A"
          )
        )
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
