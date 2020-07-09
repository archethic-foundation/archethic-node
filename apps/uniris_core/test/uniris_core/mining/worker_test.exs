defmodule UnirisCore.MiningWorkerTest do
  use UnirisCoreCase, async: false

  @moduletag capture_log: true

  alias UnirisCore.Crypto

  alias UnirisCore.BeaconSlotTimer
  alias UnirisCore.BeaconSubsetRegistry
  alias UnirisCore.BeaconSubsets

  alias UnirisCore.Election

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.CrossValidationStamp
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations
  alias UnirisCore.TransactionData

  alias UnirisCore.Mining.Context
  alias UnirisCore.Mining.Worker

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Message.AddContext
  alias UnirisCore.P2P.Message.CrossValidate
  alias UnirisCore.P2P.Message.CrossValidationDone
  alias UnirisCore.P2P.Message.GetProofOfIntegrity
  alias UnirisCore.P2P.Message.GetUnspentOutputs
  alias UnirisCore.P2P.Message.ProofOfIntegrity
  alias UnirisCore.P2P.Message.ReplicateTransaction
  alias UnirisCore.P2P.Message.UnspentOutputList
  alias UnirisCore.P2P.Node

  import Mox

  setup do
    start_supervised!({BeaconSlotTimer, interval: 0, trigger_offset: 0})
    Enum.each(BeaconSubsets.all(), &Registry.register(BeaconSubsetRegistry, &1, []))

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(),
      ready?: true,
      ready_date: DateTime.utc_now(),
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now()
    })

    {pub, _} = Crypto.generate_deterministic_keypair("seed")

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: pub,
      last_public_key: pub,
      ready?: true,
      ready_date: DateTime.utc_now(),
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      network_patch: "BBB",
      enrollment_date: DateTime.utc_now()
    })

    :ok
  end

  describe "start_link/1" do
    test "should stop the process when the validation node election is invalid" do
      tx = Transaction.new(:node, %TransactionData{})

      {:ok, pid} =
        Worker.start_link(
          transaction: tx,
          welcome_node_public_key: "",
          validation_node_public_keys: []
        )

      Process.sleep(100)
      assert !Process.alive?(pid)
    end

    test "should start mining by fetching the transaction context and elect storage nodes" do
      tx = Transaction.new(:node, %TransactionData{})
      validation_nodes = Election.validation_nodes(tx)

      previous_chain = [
        %Transaction{
          address: Crypto.hash(tx.previous_public_key),
          type: :transfer,
          timestamp: DateTime.utc_now(),
          data: %{},
          previous_public_key: "",
          previous_signature: "",
          origin_signature: "",
          validation_stamp: %ValidationStamp{
            proof_of_work: :crypto.strong_rand_bytes(32),
            proof_of_integrity: :crypto.strong_rand_bytes(32),
            ledger_operations: %LedgerOperations{},
            signature: ""
          }
        }
      ]

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          %GetUnspentOutputs{} ->
            %UnspentOutputList{}

          %GetProofOfIntegrity{} ->
            %ProofOfIntegrity{
              digest: List.first(previous_chain).validation_stamp.proof_of_integrity
            }

          %AddContext{} ->
            :ok
        end
      end)

      {:ok, pid} =
        Worker.start_link(
          transaction: tx,
          welcome_node_public_key: "",
          validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key)
        )

      assert {_,
              %{
                context: %Context{
                  chain_storage_nodes_view: _,
                  beacon_storage_nodes_view: _,
                  previous_chain: _,
                  unspent_outputs: _,
                  involved_nodes: _
                }
              }} = :sys.get_state(pid)
    end
  end

  describe "add_context/6 " do
    test "aggregate context and wait enough confirmed validation nodes context building" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "other_validator_key",
        first_public_key: "other_validator_key",
        ready?: true,
        ready_date: DateTime.utc_now(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        available?: true,
        network_patch: "AAA",
        enrollment_date: DateTime.utc_now()
      })

      tx = Transaction.new(:node, %TransactionData{})

      validation_nodes = Election.validation_nodes(tx)

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          %GetUnspentOutputs{} ->
            %UnspentOutputList{}

          %AddContext{} ->
            :ok
        end
      end)

      {:ok, coordinator_pid} =
        Worker.start_link(
          transaction: tx,
          welcome_node_public_key: "",
          validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
          node_public_key: List.first(validation_nodes).last_public_key
        )

      Worker.add_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        %Context{
          involved_nodes: ["key10", "key23"],
          cross_validation_nodes_view: <<1::1, 1::1>>,
          chain_storage_nodes_view: <<0::1, 1::1, 0::1>>,
          beacon_storage_nodes_view: <<1::1, 1::1, 0::1>>
        }
      )

      {:coordinator,
       %{
         context: %Context{
           chain_storage_nodes_view: chain_storage_nodes_view,
           beacon_storage_nodes_view: beacon_storage_nodes_view,
           cross_validation_nodes_view: cross_validation_nodes_view
         },
         confirmed_validation_nodes: confirmed_validation_nodes
       }} = :sys.get_state(coordinator_pid)

      assert cross_validation_nodes_view == <<1::1, 1::1>>
      assert chain_storage_nodes_view == <<1::1, 1::1, 1::1>>
      assert beacon_storage_nodes_view == <<1::1, 1::1, 1::1>>
      assert length(confirmed_validation_nodes) == 1
    end

    test "aggregate context and create validation stamp when enough context are retreived" do
      tx = Transaction.new(:node, %TransactionData{})
      validation_nodes = Election.validation_nodes(tx)

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          %GetUnspentOutputs{} ->
            %UnspentOutputList{}

          %AddContext{} ->
            :ok

          %CrossValidate{} ->
            :ok
        end
      end)

      {:ok, coordinator_pid} =
        Worker.start_link(
          transaction: tx,
          welcome_node_public_key: "",
          validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
          node_public_key: List.first(validation_nodes).last_public_key
        )

      Worker.add_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        %Context{
          cross_validation_nodes_view: <<1::1>>,
          chain_storage_nodes_view: <<0::1, 1::1>>,
          beacon_storage_nodes_view: <<1::1, 1::1>>,
          involved_nodes: ["key10", "key23"]
        }
      )

      {:wait_cross_validation_stamps,
       %{
         context: %Context{
           cross_validation_nodes_view: cross_validation_nodes_view,
           chain_storage_nodes_view: chain_storage_nodes_view,
           beacon_storage_nodes_view: beacon_storage_nodes_view
         },
         validation_stamp: %ValidationStamp{}
       }} = :sys.get_state(coordinator_pid)

      assert cross_validation_nodes_view == <<1::1>>
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
        ready?: true,
        ready_date: DateTime.utc_now(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        available?: true,
        network_patch: "AAA",
        enrollment_date: DateTime.utc_now()
      })

      validation_nodes = Election.validation_nodes(tx)
      me = self()

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          %GetUnspentOutputs{} ->
            %UnspentOutputList{}

          %AddContext{} ->
            :ok

          %CrossValidate{validation_stamp: stamp, replication_tree: tree} ->
            send(me, {stamp, tree})
            :ok

          %CrossValidationDone{cross_validation_stamp: stamp} ->
            send(me, {:cross_validation_done, stamp})
            :ok
        end
      end)

      {:ok, coordinator_pid} =
        Worker.start_link(
          transaction: tx,
          welcome_node_public_key: "",
          validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
          node_public_key: List.first(validation_nodes).last_public_key
        )

      {:ok, cross_validator_pid} =
        Worker.start_link(
          transaction: tx,
          welcome_node_public_key: "",
          validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
          node_public_key: List.last(validation_nodes).last_public_key
        )

      Worker.add_context(
        coordinator_pid,
        Enum.at(validation_nodes, 1).last_public_key,
        %Context{
          involved_nodes: ["key10", "key23"],
          cross_validation_nodes_view: <<1::1, 1::1>>,
          chain_storage_nodes_view: <<0::1, 1::1, 0::1>>,
          beacon_storage_nodes_view: <<1::1, 1::1>>
        }
      )

      Worker.add_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        %Context{
          involved_nodes: ["key10", "key23"],
          cross_validation_nodes_view: <<1::1, 1::1>>,
          chain_storage_nodes_view: <<0::1, 1::1, 0::1>>,
          beacon_storage_nodes_view: <<1::1, 1::1>>
        }
      )

      {:wait_cross_validation_stamps, _} = :sys.get_state(coordinator_pid)

      receive do
        {stamp = %ValidationStamp{}, tree} ->
          assert length(tree) == 3
          assert [<<0::1, 0::1, 1::1>>, <<0::1, 1::1, 0::1>>, <<1::1, 0::1, 0::1>>] = tree
          Worker.cross_validate(cross_validator_pid, stamp, tree)

          {:wait_cross_validation_stamps, %{cross_validation_stamps: cross_validation_stamps}} =
            :sys.get_state(cross_validator_pid)

          assert length(cross_validation_stamps) == 1
      end

      receive do
        {:cross_validation_done, _stamp} ->
          {_, %{validation_stamp: validation_stamp}} = :sys.get_state(coordinator_pid)

          [_ | cross_validation_nodes] = validation_nodes

          {pub, priv} = Crypto.generate_deterministic_keypair("seed")
          {pub3, priv3} = Crypto.generate_deterministic_keypair("seed3")

          cond do
            Enum.any?(cross_validation_nodes, &(&1.last_public_key == Crypto.node_public_key())) ->
              stamp = CrossValidationStamp.new(validation_stamp, [])

              Worker.add_cross_validation_stamp(coordinator_pid, stamp)

            Enum.any?(cross_validation_nodes, &(&1.last_public_key == pub)) ->
              sig =
                validation_stamp
                |> ValidationStamp.serialize()
                |> Crypto.sign(priv)

              stamp = %CrossValidationStamp{
                inconsistencies: [],
                signature: sig,
                node_public_key: pub
              }

              Worker.add_cross_validation_stamp(coordinator_pid, stamp)

            Enum.any?(cross_validation_nodes, &(&1.last_public_key == pub3)) ->
              sig =
                validation_stamp
                |> ValidationStamp.serialize()
                |> Crypto.sign(priv3)

              stamp = %CrossValidationStamp{
                inconsistencies: [],
                signature: sig,
                node_public_key: pub3
              }

              Worker.add_cross_validation_stamp(coordinator_pid, stamp)
          end

          {:wait_cross_validation_stamps, %{cross_validation_stamps: cross_validation_stamps}} =
            :sys.get_state(coordinator_pid)

          assert length(cross_validation_stamps) == 1
      end
    end

    test "should cross validate and start replication when all cross validations are received" do
      tx = Transaction.new(:node, %TransactionData{})
      validation_nodes = Election.validation_nodes(tx)
      me = self()

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          %GetUnspentOutputs{} ->
            %UnspentOutputList{}

          %AddContext{} ->
            :ok

          %CrossValidate{validation_stamp: stamp, replication_tree: tree} ->
            send(me, {stamp, tree})
            :ok

          %CrossValidationDone{cross_validation_stamp: stamp} ->
            send(me, {:cross_validation_done, stamp})
            :ok

          %ReplicateTransaction{transaction: tx} ->
            send(me, {:replicate_transaction, tx})
        end
      end)

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key10",
        first_public_key: "key10",
        ready?: true,
        ready_date: DateTime.utc_now(),
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
        ready?: true,
        ready_date: DateTime.utc_now(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        enrollment_date: DateTime.utc_now()
      })

      {:ok, coordinator_pid} =
        Worker.start_link(
          transaction: tx,
          welcome_node_public_key: "key10",
          validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
          node_public_key: List.first(validation_nodes).last_public_key
        )

      {:ok, cross_validator_pid} =
        Worker.start_link(
          transaction: tx,
          welcome_node_public_key: "key10",
          validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
          node_public_key: List.last(validation_nodes).last_public_key
        )

      Worker.add_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        %Context{
          involved_nodes: ["key10", "key23"],
          cross_validation_nodes_view: <<1::1>>,
          chain_storage_nodes_view: <<0::1, 1::1, 0::1, 1::1>>,
          beacon_storage_nodes_view: <<1::1, 1::1>>
        }
      )

      {:wait_cross_validation_stamps, _} = :sys.get_state(coordinator_pid)

      receive do
        {stamp, tree} ->
          Worker.cross_validate(cross_validator_pid, stamp, tree)

          Process.sleep(200)
          assert !Process.alive?(cross_validator_pid)
      end

      receive do
        {:cross_validation_done, _stamp} ->
          {_, %{validation_stamp: validation_stamp}} = :sys.get_state(coordinator_pid)

          if List.last(validation_nodes).last_public_key == Crypto.node_public_key() do
            stamp = %CrossValidationStamp{
              signature: Crypto.sign_with_node_key(validation_stamp),
              node_public_key: Crypto.node_public_key(),
              inconsistencies: []
            }

            Worker.add_cross_validation_stamp(coordinator_pid, stamp)
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

            Worker.add_cross_validation_stamp(coordinator_pid, stamp)
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
