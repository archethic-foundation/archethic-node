defmodule Uniris.BootstrapTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.BeaconChain.Subset, as: BeaconSubset
  alias Uniris.BeaconChain.SummaryTimer, as: BeaconSummaryTimer

  alias Uniris.Bootstrap

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.BootstrappingSeeds
  alias Uniris.P2P.Message.AcknowledgeStorage
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.BootstrappingNodes
  alias Uniris.P2P.Message.EncryptedStorageNonce
  alias Uniris.P2P.Message.GetBeaconSummary
  alias Uniris.P2P.Message.GetBootstrappingNodes
  alias Uniris.P2P.Message.GetLastTransactionAddress
  alias Uniris.P2P.Message.GetStorageNonce
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.LastTransactionAddress
  alias Uniris.P2P.Message.ListNodes
  alias Uniris.P2P.Message.NewTransaction
  alias Uniris.P2P.Message.NodeList
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Message.NotifyEndOfNodeSync
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.SelfRepair.Scheduler, as: SelfRepairScheduler

  alias Uniris.SharedSecrets.NodeRenewalScheduler

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement

  alias Uniris.PubSub

  alias Uniris.Utils

  import Mox

  setup do
    Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))
    start_supervised!({BeaconSummaryTimer, interval: "0 0 * * * * *"})
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    start_supervised!({SelfRepairScheduler, interval: "0 * * * * * *"})
    start_supervised!(BootstrappingSeeds)
    start_supervised!({NodeRenewalScheduler, interval: "0 * * * * * *"})
    start_supervised!(Batcher)

    MockDB
    |> stub(:write_transaction_chain, fn _ -> :ok end)

    on_exit(fn ->
      File.rm(Utils.mut_dir("priv/p2p/last_sync"))
    end)
  end

  describe "run/5" do
    test "should initialize the network when nothing is set before" do
      MockClient
      |> stub(:send_message, fn _, %GetLastTransactionAddress{address: address}, _ ->
        {:ok, %LastTransactionAddress{address: address}}
      end)

      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: Crypto.node_public_key(0),
          last_public_key: Crypto.node_public_key()
        }
      ]

      assert :ok = Bootstrap.run({127, 0, 0, 1}, 3000, MockTransport, seeds, DateTime.utc_now())

      assert [%Node{ip: {127, 0, 0, 1}, authorized?: true, transport: MockTransport} | _] =
               P2P.list_nodes()

      assert 1 == TransactionChain.count_transactions_by_type(:node_shared_secrets)
    end
  end

  describe "run/5 with an initialized network" do
    setup do
      me = self()

      nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key:
            <<0, 220, 205, 110, 4, 194, 222, 148, 194, 164, 97, 116, 158, 146, 181, 138, 166, 24,
              164, 86, 69, 130, 245, 19, 203, 19, 163, 2, 19, 160, 205, 9, 200>>,
          first_public_key:
            <<0, 220, 205, 110, 4, 194, 222, 148, 194, 164, 97, 116, 158, 146, 181, 138, 166, 24,
              164, 86, 69, 130, 245, 19, 203, 19, 163, 2, 19, 160, 205, 9, 200>>,
          geo_patch: "AAA",
          network_patch: "AAA",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true,
          enrollment_date: DateTime.utc_now()
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key:
            <<0, 186, 140, 57, 71, 50, 47, 229, 252, 24, 60, 6, 188, 83, 193, 145, 249, 111, 74,
              30, 113, 111, 191, 242, 155, 199, 104, 181, 21, 95, 208, 108, 146>>,
          first_public_key:
            <<0, 186, 140, 57, 71, 50, 47, 229, 252, 24, 60, 6, 188, 83, 193, 145, 249, 111, 74,
              30, 113, 111, 191, 242, 155, 199, 104, 181, 21, 95, 208, 108, 146>>,
          geo_patch: "BBB",
          network_patch: "BBB",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true,
          enrollment_date: DateTime.utc_now()
        }
      ]

      Enum.each(nodes, &P2P.add_node/1)

      MockClient
      |> stub(:send_message, fn
        _, %BatchRequests{requests: [%GetBootstrappingNodes{}]}, _ ->
          {:ok,
           %BatchResponses{
             responses: [
               {0,
                %BootstrappingNodes{
                  new_seeds: [
                    Enum.at(nodes, 0)
                  ],
                  closest_nodes: [
                    Enum.at(nodes, 1)
                  ]
                }}
             ]
           }}

        _, %NewTransaction{transaction: tx}, _ ->
          stamp = %ValidationStamp{
            proof_of_work: "",
            proof_of_integrity: "",
            ledger_operations: %LedgerOperations{
              node_movements: [
                %NodeMovement{
                  to: P2P.list_nodes() |> Enum.random() |> Map.get(:last_public_key),
                  amount: 1.0,
                  roles: [
                    :welcome_node,
                    :coordinator_node,
                    :cross_validation_node,
                    :previous_storage_node
                  ]
                }
              ]
            }
          }

          validated_tx = %{tx | validation_stamp: stamp}
          :ok = TransactionChain.write([validated_tx])
          :ok = Replication.ingest_transaction(validated_tx)
          :ok = Replication.acknowledge_storage(validated_tx)

          {:ok, %Ok{}}

        _, %GetStorageNonce{}, _ ->
          {:ok,
           %EncryptedStorageNonce{
             digest: Crypto.ec_encrypt(:crypto.strong_rand_bytes(32), Crypto.node_public_key())
           }}

        _, %ListNodes{}, _ ->
          {:ok, %NodeList{nodes: nodes}}

        _, %GetBeaconSummary{}, _ ->
          {:ok, %NotFound{}}

        _, %BatchRequests{requests: [%NotifyEndOfNodeSync{}]}, _ ->
          send(me, :node_ready)
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}

        _, %GetTransaction{address: address}, _ ->
          {:ok,
           %Transaction{
             address: address,
             validation_stamp: %ValidationStamp{},
             cross_validation_stamps: [%{}]
           }}

        _, %AcknowledgeStorage{address: address}, _ ->
          PubSub.notify_new_transaction(address)
          {:ok, %Ok{}}
      end)

      :ok
    end

    test "should add a new node" do
      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: :crypto.strong_rand_bytes(32),
          last_public_key: :crypto.strong_rand_bytes(32),
          network_patch: "AAA"
        }
      ]

      Enum.each(seeds, &P2P.add_node/1)

      assert :ok = Bootstrap.run({127, 0, 0, 1}, 3000, :tcp, seeds, DateTime.utc_now())
      assert Enum.any?(P2P.list_nodes(), &(&1.first_public_key == Crypto.node_public_key(0)))
    end

    test "should update a node" do
      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: :crypto.strong_rand_bytes(32),
          last_public_key: :crypto.strong_rand_bytes(32),
          network_patch: "AAA"
        }
      ]

      Enum.each(seeds, &P2P.add_node/1)

      assert :ok = Bootstrap.run({127, 0, 0, 1}, 3000, :tcp, seeds, DateTime.utc_now())

      %Node{
        ip: {127, 0, 0, 1},
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        transport: :tcp
      } = P2P.get_node_info()

      assert first_public_key == Crypto.node_public_key(0)
      assert last_public_key == Crypto.node_public_key(0)

      assert :ok = Bootstrap.run({200, 50, 20, 10}, 3000, :sctp, seeds, DateTime.utc_now())

      %Node{
        ip: {200, 50, 20, 10},
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        transport: :sctp
      } = P2P.get_node_info()

      assert first_public_key == Crypto.node_public_key(0)
      assert last_public_key == Crypto.node_public_key(1)
    end

    test "should not bootstrap when you are the first node and you restart the node" do
      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: :crypto.strong_rand_bytes(32),
          last_public_key: :crypto.strong_rand_bytes(32),
          network_patch: "AAA"
        }
      ]

      Enum.each(seeds, &P2P.add_node/1)

      assert :ok = Bootstrap.run({127, 0, 0, 1}, 3000, :tcp, seeds, DateTime.utc_now())

      assert %Node{ip: {127, 0, 0, 1}} = P2P.get_node_info!(Crypto.node_public_key(0))

      Process.sleep(200)
      assert :ok == Bootstrap.run({127, 0, 0, 1}, 3000, :tcp, seeds, DateTime.utc_now())

      Process.sleep(100)
    end
  end
end
