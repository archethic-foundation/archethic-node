defmodule Archethic.Mining.DistributedWorkflowTest do
  use ArchethicCase, async: false

  @moduletag capture_log: false

  alias Archethic.Crypto

  @publickey1 Crypto.generate_deterministic_keypair("seed2")
  @publickey2 Crypto.generate_deterministic_keypair("seed3")

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.SubsetRegistry

  alias Archethic.Election

  alias Archethic.Mining.DistributedWorkflow, as: Workflow
  alias Archethic.Mining.Fee
  alias Archethic.Mining.ValidationContext

  alias Archethic.P2P
  alias Archethic.P2P.Message.AddMiningContext
  alias Archethic.P2P.Message.CrossValidate
  alias Archethic.P2P.Message.CrossValidationDone
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionSummary
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Message.NotifyReplicationValidation
  alias Archethic.P2P.Message.ReplicateTransaction
  alias Archethic.P2P.Message.ReplicatePendingTransactionChain
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Message.ValidationError
  alias Archethic.P2P.Message.ValidateTransaction
  alias Archethic.P2P.Message.ReplicationAttestationMessage
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
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

    {origin_public_key, _} =
      Crypto.generate_deterministic_keypair(:crypto.strong_rand_bytes(32), :secp256r1)

    {_, ca_pv} = :crypto.generate_key(:ecdh, :secp256r1, "ca_root_key")
    <<_::8, _::8, origin_key::binary>> = origin_public_key
    certificate = Crypto.ECDSA.sign(:secp256r1, ca_pv, origin_key)

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
            origin_public_key,
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
          Election.chain_storage_nodes(tx.address, P2P.authorized_and_available_nodes()),
          P2P.authorized_and_available_nodes()
        )

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, %NotFound{}}

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
          P2P.authorized_and_available_nodes(),
          Election.chain_storage_nodes(tx.address, P2P.authorized_and_available_nodes())
        )

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, %NotFound{}}

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
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-86_400)
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
          P2P.authorized_and_available_nodes(),
          Election.chain_storage_nodes(tx.address, P2P.authorized_and_available_nodes())
        )

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, %NotFound{}}

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
          P2P.authorized_and_available_nodes(),
          Election.chain_storage_nodes(tx.address, P2P.authorized_and_available_nodes())
        )

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, %NotFound{}}

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
          P2P.authorized_and_available_nodes(),
          Election.chain_storage_nodes(tx.address, P2P.authorized_and_available_nodes())
        )

      me = self()

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, %NotFound{}}

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

      previous_storage_nodes = [
        %Node{
          ip: {80, 10, 20, 102},
          port: 3006,
          http_port: 4000,
          first_public_key: "key10",
          last_public_key: "key10",
          reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          authorized?: true,
          available?: true,
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
          available?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-86_400),
          geo_patch: "AAA",
          network_patch: "AAA"
        }
      ]

      Enum.each(previous_storage_nodes, &P2P.add_and_connect_node/1)

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
          nb_authorized_nodes = P2P.authorized_and_available_nodes() |> length()
          assert Enum.all?(chain_tree, &(bit_size(&1) == nb_authorized_nodes))
          nb_nodes = P2P.list_nodes() |> length()
          assert Enum.all?(io_tree, &(bit_size(&1) == nb_nodes))

          assert Enum.all?(beacon_tree, &(bit_size(&1) == nb_authorized_nodes))

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
          P2P.authorized_and_available_nodes(),
          Election.chain_storage_nodes(tx.address, P2P.authorized_and_available_nodes())
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

      {:ok, agent_pid} = Agent.start_link(fn -> nil end)

      MockClient
      |> stub(:send_message, fn
        _, %ValidationError{}, _ ->
          {:ok, %Ok{}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, %NotFound{}}

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

        _, %ValidateTransaction{transaction: tx}, _ ->
          Agent.update(agent_pid, fn _ -> tx end)
          {:ok, %Ok{}}

        _, %NotifyReplicationValidation{}, _ ->
          send(me, :ack_replication_validation)
          {:ok, %Ok{}}

        %Node{first_public_key: first_public_key}, %ReplicatePendingTransactionChain{}, _ ->
          tx = Agent.get(agent_pid, & &1)
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

        _, %ReplicateTransaction{}, _ ->
          {:ok, %Ok{}}

        _, %ReplicationAttestationMessage{}, _ ->
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
            :ack_replication_validation ->
              Workflow.add_replication_validation(
                coordinator_pid,
                List.first(validation_nodes).first_public_key
              )

              Workflow.add_replication_validation(
                cross_validator_pid,
                List.last(validation_nodes).first_public_key
              )
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
          refute_receive :validation_error
      end
    end

    test "should not replicate if there is a validation error", %{tx: tx} do
      validation_context = create_context(tx)

      validation_stamp = create_validation_stamp(validation_context)
      validation_stamp = %ValidationStamp{validation_stamp | error: :invalid_pending_transaction}

      context =
        validation_context
        |> ValidationContext.add_validation_stamp(validation_stamp)

      me = self()

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetUnspentOutputs{}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        _, %ValidationError{}, _ ->
          send(me, :validation_error)
          {:ok, %Ok{}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, %NotFound{}}

        _, %GetTransaction{}, _ ->
          {:ok, %Transaction{}}
      end)

      {:ok, coordinator_pid} =
        Workflow.start_link(
          transaction: context.transaction,
          welcome_node: context.welcome_node,
          validation_nodes: [context.coordinator_node | context.cross_validation_nodes],
          node_public_key: context.coordinator_node.last_public_key
        )

      :sys.replace_state(coordinator_pid, fn {:coordinator, state} ->
        {:wait_cross_validation_stamps, %{state | context: context}}
      end)

      Workflow.add_cross_validation_stamp(
        coordinator_pid,
        %CrossValidationStamp{
          signature:
            Crypto.sign(
              [ValidationStamp.serialize(context.validation_stamp), <<>>],
              elem(@publickey1, 1)
            ),
          node_public_key: elem(@publickey1, 0),
          inconsistencies: []
        }
      )

      Workflow.add_cross_validation_stamp(
        coordinator_pid,
        %CrossValidationStamp{
          signature:
            Crypto.sign(
              [ValidationStamp.serialize(context.validation_stamp), <<>>],
              elem(@publickey2, 1)
            ),
          node_public_key: elem(@publickey2, 0),
          inconsistencies: []
        }
      )

      assert_receive :validation_error
      refute_receive :ack_replication
      refute_receive :replication_done
      refute Process.alive?(coordinator_pid)
    end

    test "should not replicate if there is a cross validation error", %{tx: tx} do
      validation_context = create_context(tx)

      context =
        validation_context
        |> ValidationContext.add_validation_stamp(create_validation_stamp(validation_context))

      me = self()

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetUnspentOutputs{}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        _, %ValidationError{}, _ ->
          send(me, :validation_error)
          {:ok, %Ok{}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, %NotFound{}}

        _, %GetTransaction{}, _ ->
          {:ok, %Transaction{}}
      end)

      {:ok, coordinator_pid} =
        Workflow.start_link(
          transaction: context.transaction,
          welcome_node: context.welcome_node,
          validation_nodes: [context.coordinator_node | context.cross_validation_nodes],
          node_public_key: context.coordinator_node.last_public_key
        )

      :sys.replace_state(coordinator_pid, fn {:coordinator, state} ->
        {:wait_cross_validation_stamps, %{state | context: context}}
      end)

      Workflow.add_cross_validation_stamp(
        coordinator_pid,
        %CrossValidationStamp{
          signature:
            Crypto.sign(
              [ValidationStamp.serialize(context.validation_stamp), <<1>>],
              elem(@publickey1, 1)
            ),
          node_public_key: elem(@publickey1, 0),
          inconsistencies: [:signature]
        }
      )

      Workflow.add_cross_validation_stamp(
        coordinator_pid,
        %CrossValidationStamp{
          signature:
            Crypto.sign(
              [ValidationStamp.serialize(context.validation_stamp), <<1>>],
              elem(@publickey2, 1)
            ),
          node_public_key: elem(@publickey2, 0),
          inconsistencies: [:signature]
        }
      )

      assert_receive :validation_error
      refute_receive :ack_replication
      refute_receive :replication_done
      refute Process.alive?(coordinator_pid)
    end
  end

  defp create_context(
         tx,
         validation_time \\ DateTime.utc_now() |> DateTime.truncate(:millisecond)
       ) do
    {pub1, _} = Crypto.generate_deterministic_keypair("seed")

    welcome_node = %Node{
      last_public_key: pub1,
      first_public_key: pub1,
      geo_patch: "AAA",
      network_patch: "AAA",
      ip: {127, 0, 0, 1},
      port: 3000,
      reward_address: :crypto.strong_rand_bytes(32),
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-2)
    }

    coordinator_node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      network_patch: "AAA",
      ip: {127, 0, 0, 1},
      port: 3000,
      reward_address: :crypto.strong_rand_bytes(32),
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-2)
    }

    cross_validation_nodes = [
      %Node{
        first_public_key: elem(@publickey1, 0),
        last_public_key: elem(@publickey1, 0),
        geo_patch: "AAA",
        network_patch: "AAA",
        ip: {127, 0, 0, 1},
        port: 3000,
        reward_address: :crypto.strong_rand_bytes(32),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-2)
      },
      %Node{
        first_public_key: elem(@publickey2, 0),
        last_public_key: elem(@publickey2, 0),
        geo_patch: "AAA",
        network_patch: "AAA",
        ip: {127, 0, 0, 1},
        port: 3000,
        reward_address: :crypto.strong_rand_bytes(32),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-2)
      }
    ]

    previous_storage_nodes = [
      %Node{
        last_public_key: "key2",
        first_public_key: "key2",
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        reward_address: :crypto.strong_rand_bytes(32),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-2)
      },
      %Node{
        last_public_key: "key3",
        first_public_key: "key3",
        geo_patch: "DEA",
        network_patch: "DEA",
        available?: true,
        reward_address: :crypto.strong_rand_bytes(32),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-2)
      }
    ]

    P2P.add_and_connect_node(welcome_node)
    P2P.add_and_connect_node(coordinator_node)
    Enum.each(cross_validation_nodes, &P2P.add_and_connect_node(&1))
    Enum.each(previous_storage_nodes, &P2P.add_and_connect_node(&1))

    %ValidationContext{
      transaction: tx,
      previous_storage_nodes: previous_storage_nodes,
      unspent_outputs: [
        %UnspentOutput{
          from: "@Alice2",
          amount: 204_000_000,
          type: :UCO,
          timestamp: validation_time
        }
      ],
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      cross_validation_nodes: cross_validation_nodes,
      cross_validation_nodes_confirmation: <<1::1, 1::1>>,
      valid_pending_transaction?: true,
      validation_time: validation_time
    }
  end

  defp create_validation_stamp(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs,
         validation_time: timestamp
       }) do
    %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations:
        %LedgerOperations{
          fee: Fee.calculate(tx, 0.07, timestamp),
          transaction_movements: Transaction.get_movements(tx),
          tokens_to_mint: LedgerOperations.get_utxos_from_transaction(tx, timestamp)
        }
        |> LedgerOperations.consume_inputs(tx.address, unspent_outputs, timestamp)
        |> elem(1),
      protocol_version: ArchethicCase.current_protocol_version()
    }
  end
end
