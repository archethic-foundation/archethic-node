defmodule Archethic.Mining.DistributedWorkflowTest do
  use ArchethicCase, async: false

  @moduletag capture_log: false

  alias Archethic.Crypto

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.SubsetRegistry

  alias Archethic.Election

  alias Archethic.Mining.DistributedWorkflow, as: Workflow
  alias Archethic.Mining.ValidationContext

  alias Archethic.P2P
  alias Archethic.P2P.Message.AddMiningContext
  alias Archethic.P2P.Message.CrossValidate
  alias Archethic.P2P.Message.CrossValidationDone
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Message.ReplicateTransactionChain
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionSummary

  import Mox

  setup do
    start_supervised!({BeaconSlotTimer, interval: "* * * * * *"})
    Enum.each(BeaconChain.list_subsets(), &Registry.register(SubsetRegistry, &1, []))

    P2P.add_and_connect_node(%Node{
      ip: {80, 10, 20, 102},
      port: 3001,
      http_port: 4000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
      available?: true,
      network_patch: "AAA",
      geo_patch: "AAA",
      enrollment_date: DateTime.utc_now(),
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    {pub, _} = Crypto.generate_deterministic_keypair("seed")

    P2P.add_and_connect_node(%Node{
      ip: {80, 10, 20, 102},
      port: 3002,
      http_port: 4000,
      first_public_key: pub,
      last_public_key: pub,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
      available?: true,
      network_patch: "BBB",
      geo_patch: "BBB",
      enrollment_date: DateTime.utc_now(),
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    certificate = Crypto.get_key_certificate(Crypto.first_node_public_key())

    tx =
      Transaction.new(:node, %TransactionData{
        content:
          Node.encode_transaction_content(
            {80, 10, 20, 102},
            3000,
            4000,
            MockTransport,
            <<0, 0, 16, 233, 156, 172, 143, 228, 236, 12, 227, 76, 1, 80, 12, 236, 69, 10, 209, 6,
              234, 172, 97, 188, 240, 207, 70, 115, 64, 117, 44, 82, 132, 186>>,
            <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
            certificate
          )
      })

    {:ok,
     %{
       tx: tx,
       sorting_seed: Election.validation_nodes_election_seed_sorting(tx, ~U[2021-05-11 08:50:21Z])
     }}
  end

  describe "start_link/1" do
    test "should start mining by fetching the transaction context and elect storage nodes", %{
      tx: tx,
      sorting_seed: sorting_seed
    } do
      validation_nodes =
        Election.validation_nodes(
          tx,
          sorting_seed,
          Election.chain_storage_nodes_with_type(tx.address, tx.type, P2P.available_nodes()),
          P2P.authorized_nodes()
        )

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetUnspentOutputs{}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        _, %GetTransaction{}, _ ->
          {:ok, %Transaction{}}

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
    test "should aggregate context and wait enough confirmed validation nodes context building",
         %{tx: tx, sorting_seed: sorting_seed} do
      P2P.add_and_connect_node(%Node{
        ip: {80, 10, 20, 102},
        port: 3006,
        http_port: 4000,
        last_public_key: "other_validator_key",
        first_public_key: "other_validator_key",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
        available?: true,
        network_patch: "AAA",
        geo_patch: "AAA",
        enrollment_date: DateTime.utc_now(),
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      })

      P2P.add_and_connect_node(%Node{
        ip: {80, 10, 20, 102},
        port: 3007,
        http_port: 4000,
        last_public_key: "other_validator_key2",
        first_public_key: "other_validator_key2",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
        available?: true,
        network_patch: "DEF",
        geo_patch: "DEF",
        enrollment_date: DateTime.utc_now(),
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      })

      validation_nodes =
        Election.validation_nodes(
          tx,
          sorting_seed,
          P2P.authorized_nodes(),
          Election.chain_storage_nodes_with_type(tx.address, tx.type, P2P.available_nodes())
        )

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetUnspentOutputs{}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        _, %GetTransaction{}, _ ->
          {:ok, %Transaction{}}

        _, %AddMiningContext{}, _ ->
          {:ok, %Ok{}}
      end)

      welcome_node = %Node{
        ip: {80, 10, 20, 102},
        port: 3005,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key1",
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        geo_patch: "AAA",
        network_patch: "AAA"
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
          ip: {80, 10, 20, 102},
          port: 3006,
          http_port: 4000,
          first_public_key: "key10",
          last_public_key: "key10",
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        },
        %Node{
          ip: {80, 10, 20, 102},
          port: 3007,
          http_port: 4000,
          first_public_key: "key23",
          last_public_key: "key23",
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        }
      ]

      Workflow.add_mining_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        previous_storage_nodes,
        <<0::1, 1::1, 0::1, 1::1>>,
        <<1::1, 1::1, 0::1, 1::1>>,
        <<>>
      )

      {:coordinator,
       %{
         context: %ValidationContext{
           chain_storage_nodes_view: chain_storage_nodes_view,
           beacon_storage_nodes_view: beacon_storage_nodes_view,
           io_storage_nodes_view: io_storage_nodes_view,
           cross_validation_nodes_confirmation: confirmed_validation_nodes
         }
       }} = :sys.get_state(coordinator_pid)

      assert chain_storage_nodes_view == <<1::1, 1::1, 1::1, 1::1>>
      assert beacon_storage_nodes_view == <<1::1, 1::1, 1::1, 1::1>>
      assert io_storage_nodes_view == <<1::1, 1::1, 1::1, 1::1>>
      assert <<0::1, 1::1>> == confirmed_validation_nodes
    end

    test "aggregate context and create validation stamp when enough context are retrieved", %{
      tx: tx,
      sorting_seed: sorting_seed
    } do
      validation_nodes =
        Election.validation_nodes(
          tx,
          sorting_seed,
          P2P.authorized_nodes(),
          Election.chain_storage_nodes_with_type(tx.address, tx.type, P2P.available_nodes())
        )

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetUnspentOutputs{}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        _, %GetTransaction{}, _ ->
          {:ok, %NotFound{}}

        _, %AddMiningContext{}, _ ->
          {:ok, %Ok{}}

        _, %CrossValidate{}, _ ->
          {:ok, %Ok{}}
      end)

      welcome_node = %Node{
        ip: {80, 10, 20, 102},
        port: 3005,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key1",
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        geo_patch: "AAA",
        network_patch: "AAA"
      }

      P2P.add_and_connect_node(welcome_node)

      {:ok, coordinator_pid} =
        Workflow.start_link(
          transaction: tx,
          welcome_node: welcome_node,
          validation_nodes: validation_nodes,
          node_public_key: List.first(validation_nodes).last_public_key
        )

      previous_storage_nodes = [
        %Node{
          ip: {80, 10, 20, 102},
          port: 3006,
          http_port: 4000,
          first_public_key: "key10",
          last_public_key: "key10",
          reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        },
        %Node{
          ip: {80, 10, 20, 102},
          port: 3007,
          http_port: 4000,
          first_public_key: "key23",
          last_public_key: "key23",
          reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        }
      ]

      Enum.each(previous_storage_nodes, &P2P.add_and_connect_node/1)

      Workflow.add_mining_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        previous_storage_nodes,
        <<0::1, 1::1>>,
        <<1::1, 1::1>>,
        <<>>
      )

      {:wait_cross_validation_stamps,
       %{
         context: %ValidationContext{
           chain_storage_nodes_view: chain_storage_nodes_view,
           beacon_storage_nodes_view: beacon_storage_nodes_view,
           cross_validation_nodes_confirmation: confirmed_cross_validations,
           validation_stamp: %ValidationStamp{}
         }
       }} = :sys.get_state(coordinator_pid)

      assert confirmed_cross_validations == <<1::1>>
      assert chain_storage_nodes_view == <<1::1, 1::1>>
      assert beacon_storage_nodes_view == <<1::1, 1::1>>
    end

    test "should evict validations nodes which didn't confirm by sending their context in time",
         %{tx: tx, sorting_seed: sorting_seed} do
      {pub, _} = Crypto.generate_deterministic_keypair("seed3")

      P2P.add_and_connect_node(%Node{
        ip: {80, 10, 20, 102},
        port: 3008,
        http_port: 4000,
        last_public_key: pub,
        first_public_key: pub,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        enrollment_date: DateTime.utc_now(),
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      })

      validation_nodes =
        Election.validation_nodes(
          tx,
          sorting_seed,
          P2P.authorized_nodes(),
          Election.chain_storage_nodes_with_type(tx.address, tx.type, P2P.available_nodes())
        )

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetUnspentOutputs{}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        _, %GetTransaction{}, _ ->
          {:ok, %NotFound{}}

        _, %AddMiningContext{}, _ ->
          {:ok, %Ok{}}

        _, %CrossValidate{}, _ ->
          {:ok, %Ok{}}
      end)

      welcome_node = %Node{
        ip: {80, 10, 20, 102},
        port: 3005,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key1",
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        geo_patch: "AAA",
        network_patch: "AAA"
      }

      P2P.add_and_connect_node(welcome_node)

      {:ok, coordinator_pid} =
        Workflow.start_link(
          transaction: tx,
          welcome_node: welcome_node,
          validation_nodes: validation_nodes,
          node_public_key: List.first(validation_nodes).last_public_key
        )

      previous_storage_nodes = [
        %Node{
          ip: {80, 10, 20, 102},
          port: 3006,
          http_port: 4000,
          first_public_key: "key10",
          last_public_key: "key10",
          reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        },
        %Node{
          ip: {80, 10, 20, 102},
          port: 3007,
          http_port: 4000,
          first_public_key: "key23",
          last_public_key: "key23",
          reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        }
      ]

      Enum.each(previous_storage_nodes, &P2P.add_and_connect_node/1)

      Workflow.add_mining_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        previous_storage_nodes,
        <<0::1, 1::1>>,
        <<1::1, 1::1>>,
        <<>>
      )

      Process.sleep(4_000)

      {:wait_cross_validation_stamps,
       %{
         context: %ValidationContext{
           chain_storage_nodes_view: chain_storage_nodes_view,
           beacon_storage_nodes_view: beacon_storage_nodes_view,
           cross_validation_nodes_confirmation: confirmed_cross_validations,
           validation_stamp: %ValidationStamp{}
         }
       }} = :sys.get_state(coordinator_pid)

      assert confirmed_cross_validations == <<0::1, 1::1>>
      assert chain_storage_nodes_view == <<1::1, 1::1, 1::1>>
      assert beacon_storage_nodes_view == <<1::1, 1::1, 1::1>>
    end
  end

  describe "cross_validate/2" do
    test "should cross validate the validation stamp and the replication tree and then notify other node about it",
         %{tx: tx, sorting_seed: sorting_seed} do
      {pub, _} = Crypto.generate_deterministic_keypair("seed3")

      P2P.add_and_connect_node(%Node{
        ip: {80, 10, 20, 102},
        port: 3008,
        http_port: 4000,
        last_public_key: pub,
        first_public_key: pub,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        enrollment_date: DateTime.utc_now(),
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      })

      validation_nodes =
        Election.validation_nodes(
          tx,
          sorting_seed,
          P2P.authorized_nodes(),
          Election.chain_storage_nodes_with_type(tx.address, tx.type, P2P.available_nodes())
        )

      me = self()

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetUnspentOutputs{}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        _, %GetTransaction{}, _ ->
          {:ok, %NotFound{}}

        _, %AddMiningContext{}, _ ->
          {:ok, %Ok{}}

        _, %CrossValidate{validation_stamp: stamp, replication_tree: tree}, _ ->
          send(me, {stamp, tree})
          {:ok, %Ok{}}

        _, %CrossValidationDone{cross_validation_stamp: stamp}, _ ->
          send(me, {:cross_validation_done, stamp})
          {:ok, %Ok{}}
      end)

      welcome_node = %Node{
        ip: {80, 10, 20, 102},
        port: 3005,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key1",
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        geo_patch: "AAA",
        network_patch: "AAA"
      }

      P2P.add_and_connect_node(welcome_node)

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
          ip: {80, 10, 20, 102},
          port: 3006,
          http_port: 4000,
          first_public_key: "key10",
          last_public_key: "key10",
          reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        },
        %Node{
          ip: {80, 10, 20, 102},
          port: 3007,
          http_port: 4000,
          first_public_key: "key23",
          last_public_key: "key23",
          reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        }
      ]

      Enum.each(previous_storage_nodes, &P2P.add_and_connect_node/1)

      Workflow.add_mining_context(
        coordinator_pid,
        Enum.at(validation_nodes, 1).last_public_key,
        previous_storage_nodes,
        <<0::1, 1::1, 0::1>>,
        <<1::1, 1::1, 1::1>>,
        <<>>
      )

      Workflow.add_mining_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        previous_storage_nodes,
        <<0::1, 1::1, 0::1>>,
        <<1::1, 1::1, 1::1>>,
        <<>>
      )

      {:wait_cross_validation_stamps, _} = :sys.get_state(coordinator_pid)

      receive do
        {stamp = %ValidationStamp{},
         tree = %{chain: chain_tree, beacon: beacon_tree, IO: io_tree}} ->
          assert Enum.all?(chain_tree, &(bit_size(&1) == 3))

          assert Enum.all?(io_tree, &(bit_size(&1) == 4))

          assert Enum.all?(beacon_tree, &(bit_size(&1) == 3))

          Workflow.cross_validate(cross_validator_pid, stamp, tree, <<1::1, 1::1, 1::1>>)

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

    test "should cross validate and start replication when all cross validations are received", %{
      tx: tx,
      sorting_seed: sorting_seed
    } do
      validation_nodes =
        Election.validation_nodes(
          tx,
          sorting_seed,
          P2P.authorized_nodes(),
          Election.chain_storage_nodes_with_type(tx.address, tx.type, P2P.available_nodes())
        )

      me = self()

      storage_node_keypair = Crypto.generate_deterministic_keypair("storage_node1")

      storage_node_keypair2 = Crypto.generate_deterministic_keypair("storage_node2")

      P2P.add_and_connect_node(%Node{
        ip: {80, 10, 20, 102},
        port: 3006,
        http_port: 4000,
        last_public_key: elem(storage_node_keypair, 0),
        first_public_key: elem(storage_node_keypair, 0),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        enrollment_date: DateTime.utc_now(),
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-86_400)
      })

      P2P.add_and_connect_node(%Node{
        ip: {80, 10, 20, 102},
        port: 3007,
        http_port: 4000,
        last_public_key: elem(storage_node_keypair2, 0),
        first_public_key: elem(storage_node_keypair2, 0),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        enrollment_date: DateTime.utc_now(),
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-86_400)
      })

      welcome_node = %Node{
        ip: {80, 10, 20, 102},
        port: 3005,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key1",
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        geo_patch: "AAA",
        network_patch: "AAA"
      }

      P2P.add_and_connect_node(welcome_node)

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetUnspentOutputs{}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        _, %GetTransaction{}, _ ->
          {:ok, %NotFound{}}

        _, %AddMiningContext{}, _ ->
          {:ok, %Ok{}}

        _,
        %CrossValidate{
          validation_stamp: stamp,
          replication_tree: tree,
          confirmed_validation_nodes: confirmed_cross_validation_nodes
        },
        _ ->
          send(me, {:cross_validate, stamp, tree, confirmed_cross_validation_nodes})
          {:ok, %Ok{}}

        _, %CrossValidationDone{cross_validation_stamp: stamp}, _ ->
          send(me, {:cross_validation_done, stamp})
          {:ok, %Ok{}}

        %Node{first_public_key: first_public_key},
        %ReplicateTransactionChain{transaction: tx},
        _ ->
          tx_summary = TransactionSummary.from_transaction(tx)

          {other_validator_pub, other_validator_pv} =
            Crypto.generate_deterministic_keypair("seed")

          {sig, pub} =
            cond do
              first_public_key == Crypto.first_node_public_key() ->
                {
                  Crypto.sign_with_first_node_key(TransactionSummary.serialize(tx_summary)),
                  Crypto.first_node_public_key()
                }

              first_public_key == elem(storage_node_keypair, 0) ->
                {Crypto.sign(
                   TransactionSummary.serialize(tx_summary),
                   elem(storage_node_keypair, 1)
                 ), elem(storage_node_keypair, 0)}

              first_public_key == elem(storage_node_keypair2, 0) ->
                {
                  Crypto.sign(
                    TransactionSummary.serialize(tx_summary),
                    elem(storage_node_keypair2, 1)
                  ),
                  elem(storage_node_keypair2, 0)
                }

              first_public_key == other_validator_pub ->
                {Crypto.sign(
                   TransactionSummary.serialize(tx_summary),
                   other_validator_pv
                 ), other_validator_pub}
            end

          send(me, {:ack_replication, sig, pub})

          {:ok, %Ok{}}

        _, %ReplicationAttestation{}, _ ->
          send(me, :replication_done)
          {:ok, %Ok{}}
      end)

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
          ip: {80, 10, 20, 102},
          port: 3007,
          http_port: 4000,
          first_public_key: elem(storage_node_keypair, 0),
          last_public_key: elem(storage_node_keypair, 0),
          reward_address: :crypto.strong_rand_bytes(32),
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        },
        %Node{
          ip: {80, 10, 20, 102},
          port: 3008,
          http_port: 4000,
          first_public_key: elem(storage_node_keypair2, 0),
          last_public_key: elem(storage_node_keypair2, 0),
          reward_address: :crypto.strong_rand_bytes(32),
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        }
      ]

      Enum.each(previous_storage_nodes, &P2P.add_and_connect_node/1)

      Workflow.add_mining_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        previous_storage_nodes,
        <<0::1, 1::1, 0::1, 1::1>>,
        <<1::1, 1::1, 1::1, 1::1>>,
        <<>>
      )

      {:wait_cross_validation_stamps, _} = :sys.get_state(coordinator_pid)

      receive do
        {:cross_validate, stamp, tree, confirmed_cross_validation_nodes} ->
          Workflow.cross_validate(
            cross_validator_pid,
            stamp,
            tree,
            confirmed_cross_validation_nodes
          )
      end

      receive do
        {:cross_validation_done, _stamp} ->
          {_, %{context: %ValidationContext{validation_stamp: validation_stamp}}} =
            :sys.get_state(coordinator_pid)

          if List.last(validation_nodes).last_public_key == Crypto.last_node_public_key() do
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

          receive do
            {:ack_replication, sig, pub} ->
              send(coordinator_pid, {:ack_replication, sig, pub})
          end

          receive do
            {:ack_replication, sig, pub} ->
              send(cross_validator_pid, {:ack_replication, sig, pub})
          end

          receive do
            {:ack_replication, sig, pub} ->
              send(cross_validator_pid, {:ack_replication, sig, pub})
          end

          receive do
            {:ack_replication, sig, pub} ->
              send(coordinator_pid, {:ack_replication, sig, pub})
          end

          assert_receive :replication_done
      end
    end
  end
end
