defmodule Uniris.ReplicationTest do
  use UnirisCase, async: false

  alias Uniris.Crypto

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.BeaconChain.SubsetRegistry, as: BeaconSubsetRegistry

  alias Uniris.BeaconChain.Subset, as: BeaconSubset

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.NotifyLastTransactionAddress
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.SharedSecrets

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionData

  doctest Uniris.Replication

  import Mox

  setup do
    start_supervised!({BeaconSlotTimer, [interval: "* * * * * *"]})
    start_supervised!(Batcher)
    :ok
  end

  describe "chain_storage_node/2" do
    test "when the transaction is a network transaction, all the nodes are involved" do
      nodes =
        Enum.map(1..200, fn i ->
          %Node{
            ip: {88, 130, 19, i},
            port: 3000 + i,
            last_public_key: :crypto.strong_rand_bytes(32),
            first_public_key: :crypto.strong_rand_bytes(32),
            geo_patch: random_patch(),
            available?: true,
            authorized?: rem(i, 7) == 0,
            authorization_date: DateTime.utc_now()
          }
        end)

      Enum.each(nodes, &P2P.add_node/1)

      chain_storage_nodes =
        Replication.chain_storage_nodes("@Node1", :node, P2P.list_nodes())
        |> Enum.map(& &1.last_public_key)

      assert Enum.all?(nodes, &(&1.last_public_key in chain_storage_nodes))
    end

    test "when the transaction is not a network transaction, a shared of nodes is used" do
      nodes =
        Enum.map(1..200, fn i ->
          %Node{
            ip: {88, 130, 19, i},
            port: 3000 + i,
            last_public_key: :crypto.strong_rand_bytes(32),
            first_public_key: :crypto.strong_rand_bytes(32),
            geo_patch: random_patch(),
            available?: true,
            authorized?: rem(i, 7) == 0,
            authorization_date: DateTime.utc_now()
          }
        end)

      Enum.each(nodes, &P2P.add_node/1)

      chain_storage_nodes =
        Replication.chain_storage_nodes("@Alice2", :transfer, P2P.list_nodes())
        |> Enum.map(& &1.last_public_key)

      assert !Enum.all?(nodes, &(&1.last_public_key in chain_storage_nodes))
    end
  end

  test "beacon_storage_nodes/2 should list the beacon storage nodes authorized before the transaction timestamp" do
    nodes = [
      %Node{
        ip: {88, 130, 19, 0},
        port: 3002,
        last_public_key: :crypto.strong_rand_bytes(32),
        first_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: random_patch(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      },
      %Node{
        ip: {88, 130, 19, 1},
        port: 3005,
        last_public_key: :crypto.strong_rand_bytes(32),
        first_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: random_patch(),
        available?: true,
        authorized?: false
      },
      %Node{
        ip: {88, 130, 19, 2},
        port: 3008,
        last_public_key: :crypto.strong_rand_bytes(32),
        first_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: random_patch(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-10)
      }
    ]

    Enum.each(nodes, &P2P.add_node/1)

    beacon_storage_nodes = Replication.beacon_storage_nodes("@Alice2", DateTime.utc_now())

    beacon_storage_nodes_ip = Enum.map(beacon_storage_nodes, & &1.ip)
    assert Enum.all?([{88, 130, 19, 2}, {88, 130, 19, 0}], &(&1 in beacon_storage_nodes_ip))
  end

  defp random_patch do
    list_char = Enum.concat([?0..?9, ?A..?F])
    Enum.take_random(list_char, 3) |> List.to_string()
  end

  test "process_transaction/2" do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      authorized?: true,
      last_public_key: Crypto.node_public_key(),
      first_public_key: Crypto.node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorization_date: DateTime.utc_now() |> DateTime.add(-10)
    })

    Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))

    me = self()

    unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 10.0, type: :UCO}]
    tx = create_valid_transaction(transaction_context(), unspent_outputs)

    MockDB
    |> expect(:write_transaction_chain, fn _ ->
      send(me, :replicated)
      :ok
    end)

    MockClient
    |> stub(:send_message, fn
      _, %BatchRequests{requests: [%GetUnspentOutputs{}, %GetTransactionChain{}]}, _ ->
        {:ok,
         %BatchResponses{
           responses: [
             {0, %UnspentOutputList{unspent_outputs: unspent_outputs}},
             {1, %TransactionList{transactions: []}}
           ]
         }}
    end)

    assert :ok = Replication.process_transaction(tx, [:chain, :beacon])

    Process.sleep(200)

    assert_received :replicated

    subset = BeaconChain.subset_from_address(tx.address)
    [{pid, _}] = Registry.lookup(BeaconSubsetRegistry, subset)

    assert %{current_slot: %Slot{transaction_summaries: [%TransactionSummary{}]}} =
             :sys.get_state(pid)
  end

  defp transaction_context do
    SharedSecrets.add_origin_public_key(:software, Crypto.node_public_key(0))

    welcome_node = %Node{
      first_public_key: "key1",
      last_public_key: "key1",
      available?: true,
      geo_patch: "BBB",
      network_patch: "BBB"
    }

    coordinator_node = %Node{
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now(),
      geo_patch: "AAA",
      network_patch: "AAA"
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB"
      }
    ]

    Enum.each(storage_nodes, &P2P.add_node(&1))

    P2P.add_node(welcome_node)
    P2P.add_node(coordinator_node)

    %{
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      storage_nodes: storage_nodes
    }
  end

  defp create_valid_transaction(
         %{
           welcome_node: welcome_node,
           coordinator_node: coordinator_node,
           storage_nodes: storage_nodes
         },
         unspent_outputs
       ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        # TODO: change when the fee algorithm will be implemented
        fee: 0.01
      }
      |> LedgerOperations.distribute_rewards(
        welcome_node,
        coordinator_node,
        [coordinator_node],
        [welcome_node, coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, unspent_outputs)

    validation_stamp =
      %ValidationStamp{
        proof_of_work: Crypto.node_public_key(0),
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
      |> stub(:add_last_transaction_address, fn _address, _last_address ->
        :ok
      end)

      assert :ok = Replication.acknowledge_previous_storage_nodes("@Alice2", "@Alice1")
      assert "@Alice2" == TransactionChain.get_last_address("@Alice1")
    end

    test "should notify previous storage pool if transaction exists" do
      MockDB
      |> stub(:add_last_transaction_address, fn _address, _last_address ->
        :ok
      end)
      |> stub(:get_transaction, fn _, _ ->
        {:ok, %Transaction{previous_public_key: "Alice1"}}
      end)

      me = self()

      MockClient
      |> stub(:send_message, fn _,
                                %BatchRequests{
                                  requests: [%NotifyLastTransactionAddress{address: _}]
                                },
                                _ ->
        send(me, :notification_sent)
        {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
      end)

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: "AAA",
        available?: true
      })

      assert :ok = Replication.acknowledge_previous_storage_nodes("@Alice2", "@Alice1")
      assert "@Alice2" == TransactionChain.get_last_address("@Alice1")

      assert_receive :notification_sent, 500
    end
  end
end
