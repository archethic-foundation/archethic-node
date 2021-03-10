defmodule Uniris.Mining.DistributedWorkflowTest do
  use UnirisCase, async: false

  @moduletag capture_log: false

  alias Uniris.Crypto

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.BeaconChain.SubsetRegistry

  alias Uniris.Election

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  alias Uniris.Mining.DistributedWorkflow, as: Workflow
  alias Uniris.Mining.ValidationContext

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.AddMiningContext
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.CrossValidate
  alias Uniris.P2P.Message.CrossValidationDone
  alias Uniris.P2P.Message.GetP2PView
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Message.P2PView
  alias Uniris.P2P.Message.ReplicateTransaction
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  import Mox

  setup do
    start_supervised!({BeaconSlotTimer, interval: "* * * * * *"})
    Enum.each(BeaconChain.list_subsets(), &Registry.register(SubsetRegistry, &1, []))
    start_supervised!(Batcher)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(),
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      network_patch: "AAA",
      geo_patch: "AAA",
      enrollment_date: DateTime.utc_now()
    })

    {pub, _} = Crypto.generate_deterministic_keypair("seed")

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: pub,
      last_public_key: pub,
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      network_patch: "BBB",
      geo_patch: "BBB",
      enrollment_date: DateTime.utc_now()
    })

    :ok
  end

  describe "start_link/1" do
    test "should start mining by fetching the transaction context and elect storage nodes" do
      tx = Transaction.new(:node, %TransactionData{})

      validation_nodes =
        Election.validation_nodes(tx, P2P.list_nodes(authorized?: true, availability: :global))

      MockClient
      |> stub(:send_message, fn
        _,
        %BatchRequests{
          requests: [
            %GetP2PView{node_public_keys: public_keys1},
            %GetP2PView{node_public_keys: public_keys2},
            %GetUnspentOutputs{},
            %GetTransaction{}
          ]
        },
        _ ->
          view1 = Enum.reduce(public_keys1, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)
          view2 = Enum.reduce(public_keys2, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %P2PView{nodes_view: view2}},
               {2, %UnspentOutputList{}},
               {3, %Transaction{}}
             ]
           }}

        _,
        %BatchRequests{
          requests: [
            %GetP2PView{node_public_keys: public_keys1},
            %GetUnspentOutputs{},
            %GetTransaction{}
          ]
        },
        _ ->
          view1 = Enum.reduce(public_keys1, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %UnspentOutputList{}},
               {2, %Transaction{}}
             ]
           }}

        _, %AddMiningContext{}, _ ->
          {:ok, %Ok{}}
      end)

      {:ok, pid} =
        Workflow.start_link(
          transaction: tx,
          welcome_node: %Node{},
          validation_nodes: validation_nodes
        )

      assert {_,
              %{
                context: %ValidationContext{
                  chain_storage_nodes_view: _,
                  beacon_storage_nodes_view: _,
                  previous_transaction: _,
                  unspent_outputs: _,
                  previous_storage_nodes: _
                }
              }} = :sys.get_state(pid)
    end
  end

  describe "add_mining_context/6" do
    test "should aggregate context and wait enough confirmed validation nodes context building" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "other_validator_key",
        first_public_key: "other_validator_key",
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        available?: true,
        network_patch: "AAA",
        geo_patch: "AAA",
        enrollment_date: DateTime.utc_now()
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "other_validator_key2",
        first_public_key: "other_validator_key2",
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        available?: true,
        network_patch: "DEF",
        geo_patch: "DEF",
        enrollment_date: DateTime.utc_now()
      })

      tx = Transaction.new(:node, %TransactionData{})

      validation_nodes =
        Election.validation_nodes(tx, P2P.list_nodes(authorized?: true, availability: :global))

      MockClient
      |> stub(:send_message, fn
        _,
        %BatchRequests{
          requests: [
            %GetP2PView{node_public_keys: public_keys1},
            %GetP2PView{node_public_keys: public_keys2}
          ]
        },
        _ ->
          view1 = Enum.reduce(public_keys1, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)
          view2 = Enum.reduce(public_keys2, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %P2PView{nodes_view: view2}}
             ]
           }}

        _, %BatchRequests{requests: [%GetP2PView{node_public_keys: public_keys2}]}, _ ->
          view2 = Enum.reduce(public_keys2, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view2}}
             ]
           }}

        _,
        %BatchRequests{
          requests: [
            %GetP2PView{node_public_keys: public_keys1},
            %GetUnspentOutputs{},
            %GetTransaction{}
          ]
        },
        _ ->
          view1 = Enum.reduce(public_keys1, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %UnspentOutputList{}},
               {2, %Transaction{}}
             ]
           }}

        _, %AddMiningContext{}, _ ->
          {:ok, %Ok{}}
      end)

      welcome_node = %Node{
        ip: {127, 0, 0, 1},
        port: 3005,
        first_public_key: "key1",
        last_public_key: "key1"
      }

      {:ok, coordinator_pid} =
        Workflow.start_link(
          transaction: tx,
          welcome_node_public_key: welcome_node,
          validation_nodes: validation_nodes,
          node_public_key: List.first(validation_nodes).last_public_key
        )

      previous_storage_nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key10",
          last_public_key: "key10"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          first_public_key: "key23",
          last_public_key: "key23"
        }
      ]

      Workflow.add_mining_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        previous_storage_nodes,
        <<1::1, 1::1, 1::1>>,
        <<0::1, 1::1, 0::1, 1::1>>,
        <<1::1, 1::1, 0::1, 1::1>>
      )

      {:coordinator,
       %{
         context: %ValidationContext{
           chain_storage_nodes_view: chain_storage_nodes_view,
           beacon_storage_nodes_view: beacon_storage_nodes_view,
           validation_nodes_view: validation_nodes_view,
           cross_validation_nodes_confirmation: confirmed_validation_nodes
         }
       }} = :sys.get_state(coordinator_pid)

      assert validation_nodes_view == <<1::1, 1::1, 1::1>>
      assert chain_storage_nodes_view == <<1::1, 1::1, 1::1, 1::1>>
      assert beacon_storage_nodes_view == <<1::1, 1::1, 1::1, 1::1>>
      assert <<0::1, 1::1>> == confirmed_validation_nodes
    end

    test "aggregate context and create validation stamp when enough context are retrieved" do
      tx = Transaction.new(:node, %TransactionData{})

      validation_nodes =
        Election.validation_nodes(tx, P2P.list_nodes(authorized?: true, availability: :global))

      MockClient
      |> stub(:send_message, fn
        _,
        %BatchRequests{
          requests: [
            %GetP2PView{node_public_keys: public_keys},
            %GetTransaction{}
          ]
        },
        _ ->
          view1 = Enum.reduce(public_keys, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %NotFound{}}
             ]
           }}

        _,
        %BatchRequests{
          requests: [
            %GetP2PView{node_public_keys: public_keys},
            %GetUnspentOutputs{},
            %GetTransaction{}
          ]
        },
        _ ->
          view1 = Enum.reduce(public_keys, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %UnspentOutputList{}},
               {2, %NotFound{}}
             ]
           }}

        _,
        %BatchRequests{
          requests: [
            %GetP2PView{node_public_keys: public_keys1},
            %GetP2PView{node_public_keys: public_keys2},
            %GetUnspentOutputs{},
            %GetTransaction{}
          ]
        },
        _ ->
          view1 = Enum.reduce(public_keys1, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)
          view2 = Enum.reduce(public_keys2, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %P2PView{nodes_view: view2}},
               {2, %UnspentOutputList{}},
               {3, %NotFound{}}
             ]
           }}

        _, %AddMiningContext{}, _ ->
          {:ok, %Ok{}}

        _, %BatchRequests{requests: [%CrossValidate{}]}, _ ->
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
      end)

      welcome_node = %Node{
        ip: {127, 0, 0, 1},
        port: 3005,
        first_public_key: "key1",
        last_public_key: "key1"
      }

      {:ok, coordinator_pid} =
        Workflow.start_link(
          transaction: tx,
          welcome_node: welcome_node,
          validation_nodes: validation_nodes,
          node_public_key: List.first(validation_nodes).last_public_key
        )

      previous_storage_nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key10",
          last_public_key: "key10"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          first_public_key: "key23",
          last_public_key: "key23"
        }
      ]

      Workflow.add_mining_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        previous_storage_nodes,
        <<1::1, 1::1>>,
        <<0::1, 1::1>>,
        <<1::1, 1::1>>
      )

      {:wait_cross_validation_stamps,
       %{
         context: %ValidationContext{
           validation_nodes_view: validation_nodes_view,
           chain_storage_nodes_view: chain_storage_nodes_view,
           beacon_storage_nodes_view: beacon_storage_nodes_view,
           cross_validation_nodes_confirmation: confirmed_cross_validations,
           validation_stamp: %ValidationStamp{}
         }
       }} = :sys.get_state(coordinator_pid)

      assert validation_nodes_view == <<1::1, 1::1>>
      assert confirmed_cross_validations == <<1::1>>
      assert chain_storage_nodes_view == <<1::1, 1::1>>
      assert beacon_storage_nodes_view == <<1::1, 1::1>>
    end
  end

  describe "cross_validate/2" do
    test "should cross validate the validation stamp and the replication tree and then notify other node about it" do
      tx = Transaction.new(:node, %TransactionData{})

      {pub, _} = Crypto.generate_deterministic_keypair("seed3")

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: pub,
        first_public_key: pub,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        enrollment_date: DateTime.utc_now()
      })

      validation_nodes =
        Election.validation_nodes(tx, P2P.list_nodes(authorized?: true, availability: :global))

      me = self()

      MockClient
      |> stub(:send_message, fn
        _,
        %BatchRequests{
          requests: [
            %GetP2PView{node_public_keys: public_keys1},
            %GetUnspentOutputs{},
            %GetTransaction{}
          ]
        },
        _ ->
          view1 = Enum.reduce(public_keys1, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %UnspentOutputList{}},
               {2, %NotFound{}}
             ]
           }}

        _, %BatchRequests{requests: [%GetP2PView{node_public_keys: public_keys2}]}, _ ->
          view2 = Enum.reduce(public_keys2, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view2}}
             ]
           }}

        _,
        %BatchRequests{
          requests: [
            %GetP2PView{node_public_keys: public_keys1},
            %GetP2PView{node_public_keys: public_keys2},
            %GetUnspentOutputs{},
            %GetTransaction{}
          ]
        },
        _ ->
          view1 = Enum.reduce(public_keys1, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)
          view2 = Enum.reduce(public_keys2, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %P2PView{nodes_view: view2}},
               {2, %UnspentOutputList{}},
               {3, %NotFound{}}
             ]
           }}

        _, %AddMiningContext{}, _ ->
          {:ok, %Ok{}}

        _,
        %BatchRequests{
          requests: [%CrossValidate{validation_stamp: stamp, replication_tree: tree}]
        },
        _ ->
          send(me, {stamp, tree})
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}

        _, %BatchRequests{requests: [%CrossValidationDone{cross_validation_stamp: stamp}]}, _ ->
          send(me, {:cross_validation_done, stamp})
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
      end)

      welcome_node = %Node{
        ip: {127, 0, 0, 1},
        port: 3005,
        first_public_key: "key1",
        last_public_key: "key1"
      }

      {:ok, coordinator_pid} =
        Workflow.start_link(
          transaction: tx,
          welcome_node: welcome_node,
          validation_nodes: validation_nodes,
          node_public_key: List.first(validation_nodes).last_public_key
        )

      {:ok, cross_validator_pid} =
        Workflow.start_link(
          transaction: tx,
          welcome_node: welcome_node,
          validation_nodes: validation_nodes,
          node_public_key: List.last(validation_nodes).last_public_key
        )

      previous_storage_nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key10",
          last_public_key: "key10"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          first_public_key: "key23",
          last_public_key: "key23"
        }
      ]

      Workflow.add_mining_context(
        coordinator_pid,
        Enum.at(validation_nodes, 1).last_public_key,
        previous_storage_nodes,
        <<1::1, 1::1, 1::1>>,
        <<0::1, 1::1, 0::1>>,
        <<1::1, 1::1, 1::1>>
      )

      Workflow.add_mining_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        previous_storage_nodes,
        <<1::1, 1::1, 1::1>>,
        <<0::1, 1::1, 0::1>>,
        <<1::1, 1::1, 1::1>>
      )

      {:wait_cross_validation_stamps, _} = :sys.get_state(coordinator_pid)

      receive do
        {stamp = %ValidationStamp{}, tree} ->
          assert [<<0::1, 1::1, 0::1>>, <<0::1, 0::1, 1::1>>, <<1::1, 0::1, 0::1>>] = tree
          Workflow.cross_validate(cross_validator_pid, stamp, tree)

          {:wait_cross_validation_stamps,
           %{context: %ValidationContext{cross_validation_stamps: cross_validation_stamps}}} =
            :sys.get_state(cross_validator_pid)

          assert length(cross_validation_stamps) == 1
      end

      receive do
        {:cross_validation_done, _stamp} ->
          {:wait_cross_validation_stamps,
           %{context: %ValidationContext{validation_stamp: validation_stamp}}} =
            :sys.get_state(coordinator_pid)

          [_ | cross_validation_nodes] = validation_nodes

          {pub, priv} = Crypto.generate_deterministic_keypair("seed")
          {pub3, priv3} = Crypto.generate_deterministic_keypair("seed3")

          if Enum.any?(cross_validation_nodes, &(&1.last_public_key == pub)) do
            sig =
              validation_stamp
              |> ValidationStamp.serialize()
              |> Crypto.sign(priv)

            stamp = %CrossValidationStamp{
              inconsistencies: [],
              signature: sig,
              node_public_key: pub
            }

            Workflow.add_cross_validation_stamp(coordinator_pid, stamp)
          else
            sig =
              validation_stamp
              |> ValidationStamp.serialize()
              |> Crypto.sign(priv3)

            stamp = %CrossValidationStamp{
              inconsistencies: [],
              signature: sig,
              node_public_key: pub3
            }

            Workflow.add_cross_validation_stamp(coordinator_pid, stamp)
          end

          {:wait_cross_validation_stamps,
           %{context: %ValidationContext{cross_validation_stamps: cross_validation_stamps}}} =
            :sys.get_state(coordinator_pid)

          assert length(cross_validation_stamps) == 1
      end
    end

    test "should cross validate and start replication when all cross validations are received" do
      tx = Transaction.new(:node, %TransactionData{})

      validation_nodes =
        Election.validation_nodes(tx, P2P.list_nodes(authorized?: true, availability: :global))

      me = self()

      MockClient
      |> stub(:send_message, fn
        _,
        %BatchRequests{
          requests: [%GetP2PView{node_public_keys: public_keys1}, %GetUnspentOutputs{}]
        },
        _ ->
          view1 = Enum.reduce(public_keys1, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %UnspentOutputList{}}
             ]
           }}

        _,
        %BatchRequests{requests: [%GetP2PView{node_public_keys: public_keys1}, %GetTransaction{}]},
        _ ->
          view1 = Enum.reduce(public_keys1, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view1}},
               {1, %NotFound{}}
             ]
           }}

        _, %BatchRequests{requests: [%GetP2PView{node_public_keys: public_keys2}]}, _ ->
          view2 = Enum.reduce(public_keys2, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end)

          {:ok,
           %BatchResponses{
             responses: [
               {0, %P2PView{nodes_view: view2}}
             ]
           }}

        _, %AddMiningContext{}, _ ->
          {:ok, %Ok{}}

        _,
        %BatchRequests{
          requests: [%CrossValidate{validation_stamp: stamp, replication_tree: tree}]
        },
        _ ->
          send(me, {:cross_validate, stamp, tree})
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}

        _, %BatchRequests{requests: [%CrossValidationDone{cross_validation_stamp: stamp}]}, _ ->
          send(me, {:cross_validation_done, stamp})
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}

        _, %ReplicateTransaction{transaction: tx}, _ ->
          send(me, {:replicate_transaction, tx})
          {:ok, %Ok{}}
      end)

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key10",
        first_public_key: "key10",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        enrollment_date: DateTime.utc_now()
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key23",
        first_public_key: "key23",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        enrollment_date: DateTime.utc_now()
      })

      welcome_node = %Node{
        ip: {127, 0, 0, 1},
        port: 3005,
        first_public_key: "key1",
        last_public_key: "key1"
      }

      {:ok, coordinator_pid} =
        Workflow.start_link(
          transaction: tx,
          welcome_node: welcome_node,
          validation_nodes: validation_nodes,
          node_public_key: List.first(validation_nodes).last_public_key
        )

      {:ok, cross_validator_pid} =
        Workflow.start_link(
          transaction: tx,
          welcome_node: welcome_node,
          validation_nodes: validation_nodes,
          node_public_key: List.last(validation_nodes).last_public_key
        )

      previous_storage_nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key10",
          last_public_key: "key10"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          first_public_key: "key23",
          last_public_key: "key23"
        }
      ]

      Workflow.add_mining_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        previous_storage_nodes,
        <<1::1, 1::1>>,
        <<0::1, 1::1, 0::1, 1::1>>,
        <<1::1, 1::1, 1::1, 1::1>>
      )

      {:wait_cross_validation_stamps, _} = :sys.get_state(coordinator_pid)

      receive do
        {:cross_validate, stamp, tree} ->
          Workflow.cross_validate(cross_validator_pid, stamp, tree)

          Process.sleep(200)
          assert !Process.alive?(cross_validator_pid)
      end

      receive do
        {:cross_validation_done, _stamp} ->
          {_, %{context: %ValidationContext{validation_stamp: validation_stamp}}} =
            :sys.get_state(coordinator_pid)

          if List.last(validation_nodes).last_public_key == Crypto.node_public_key() do
            stamp = CrossValidationStamp.sign(%CrossValidationStamp{}, validation_stamp)
            Workflow.add_cross_validation_stamp(coordinator_pid, stamp)
          else
            {pub, priv} = Crypto.generate_deterministic_keypair("seed")

            sig =
              validation_stamp
              |> ValidationStamp.serialize()
              |> Crypto.sign(priv)

            stamp = %CrossValidationStamp{
              signature: sig,
              node_public_key: pub,
              inconsistencies: []
            }

            Workflow.add_cross_validation_stamp(coordinator_pid, stamp)
          end

          Process.sleep(200)
          assert !Process.alive?(coordinator_pid)

          receive do
            {:replicate_transaction, %Transaction{cross_validation_stamps: stamps}} ->
              assert length(stamps) == 1
          end
      end
    end
  end
end
