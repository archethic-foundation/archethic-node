defmodule UnirisCore.MiningWorkerTest do
  use UnirisCoreCase, async: false

  @moduletag capture_log: true

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements
  alias UnirisCore.Transaction.ValidationStamp.NodeMovements
  alias UnirisCore.Mining.Worker
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.Crypto
  alias UnirisCore.Election
  alias UnirisCore.BeaconSlotTimer
  alias UnirisCore.BeaconSubsets
  alias UnirisCore.BeaconSubsetRegistry

  import Mox

  setup do
    start_supervised!(UnirisCore.Storage.Cache)
    start_supervised!({BeaconSlotTimer, slot_interval: 10_000})
    Enum.each(BeaconSubsets.all(), &Registry.register(BeaconSubsetRegistry, &1, []))

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(),
      ready?: true,
      authorized?: true,
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
      authorized?: true,
      available?: true,
      network_patch: "BBB",
      enrollment_date: DateTime.utc_now()
    })

    MockStorage
    |> stub(:node_transactions, fn -> [] end)

    :ok
  end

  describe "start_link/1" do
    test "should stop the process when the transaction is invalid" do
      tx = %Transaction{
        address: :crypto.strong_rand_bytes(32),
        type: :transfer,
        timestamp: DateTime.utc_now(),
        data: %{},
        previous_public_key: "",
        previous_signature: "",
        origin_signature: ""
      }

      {:ok, pid} =
        Worker.start_link(
          transaction: tx,
          welcome_node_public_key: "",
          validation_node_public_keys: []
        )

      Process.sleep(100)
      assert !Process.alive?(pid)
    end

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

      unspent_outputs = [
        %Transaction{
          address: :crypto.strong_rand_bytes(32),
          type: :transfer,
          timestamp: DateTime.utc_now(),
          data: %{},
          previous_public_key: "",
          previous_signature: "",
          origin_signature: ""
        }
      ]

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
            ledger_movements: %LedgerMovements{},
            node_movements: %NodeMovements{fee: 1, rewards: []},
            signature: ""
          }
        }
      ]

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
            [{:ok, previous_chain}, {:ok, unspent_outputs}]

          {:get_transaction, _} ->
            {:ok, List.first(unspent_outputs)}

          {:get_proof_of_integrity, _} ->
            {:ok, List.first(previous_chain).validation_stamp.proof_of_integrity}

          {:add_context, _addr, _validator_key, _previous_storage_nodes, _validation_node_view,
           _chain_storage_nodes_view, _beacon_storage_nodes_view} ->
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
                chain_storage_nodes: _,
                beacon_storage_nodes: _,
                chain_storage_nodes_view: _,
                beacon_storage_nodes_view: _,
                previous_chain: _,
                unspent_outputs: _,
                previous_storage_nodes: _
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
        authorized?: true,
        available?: true,
        network_patch: "AAA",
        enrollment_date: DateTime.utc_now()
      })

      tx = Transaction.new(:node, %TransactionData{})

      validation_nodes = Election.validation_nodes(tx)

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
            [
              {:error, :transaction_chain_not_exists},
              {:error, :unspent_output_transactions_not_exists}
            ]

          {:add_context, _addr, _validator_key, _previous_storage_nodes,
           _cross_validation_nodes_view, _chain_storage_nodes_view, _beacon_storage_nodes_view} ->
            nil
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
        ["key10", "key23"],
        <<1::1, 1::1>>,
        <<0::1, 1::1, 0::1>>,
        <<1::1, 1::1, 0::1>>
      )

      {:coordinator,
       %{
         cross_validation_nodes_view: cross_validation_nodes_view,
         chain_storage_nodes_view: chain_storage_nodes_view,
         beacon_storage_nodes_view: beacon_storage_nodes_view,
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
          [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
            [
              {:error, :transaction_chain_not_exists},
              {:error, :unspent_output_transactions_not_exists}
            ]

          {:add_context, _addr, _validator_key, _previous_storage_nodes,
           _cross_validation_nodes_view, _chain_storage_nodes_view, _beacon_storage_nodes_view} ->
            :ok

          [{:set_replication_trees, _, _, _}, {:cross_validate, _, _stamp}] ->
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
        ["key10", "key23"],
        <<1::1>>,
        <<0::1, 1::1>>,
        <<1::1, 1::1>>
      )

      {:wait_cross_validation_stamps,
       %{
         cross_validation_nodes_view: cross_validation_nodes_view,
         chain_storage_nodes_view: chain_storage_nodes_view,
         beacon_storage_nodes_view: beacon_storage_nodes_view,
         validation_stamp: %ValidationStamp{}
       }} = :sys.get_state(coordinator_pid)

      assert cross_validation_nodes_view == <<1::1>>
      assert chain_storage_nodes_view == <<1::1, 1::1>>
      assert beacon_storage_nodes_view == <<1::1, 1::1>>
    end
  end

  test "set_replication_trees/2 should extract replication nodes from the storage trees" do
    tx = Transaction.new(:node, %TransactionData{})
    validation_nodes = Election.validation_nodes(tx)

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
          [
            {:error, :transaction_chain_not_exists},
            {:error, :unspent_output_transactions_not_exists}
          ]

        {:add_context, _addr, _validator_key, _previous_storage_nodes,
         _cross_validation_nodes_view, _chain_storage_nodes_view, _beacon_storage_nodes_view} ->
          :ok
      end
    end)

    {:ok, cross_validator_pid} =
      Worker.start_link(
        transaction: tx,
        welcome_node_public_key: "",
        validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
        node_public_key: List.last(validation_nodes).last_public_key
      )

    Worker.set_replication_trees(
      cross_validator_pid,
      [<<1::1, 0::1>>, <<0::1, 1::1>>],
      [<<0::1, 1::1>>, <<1::1, 0::1>>]
    )

    assert {:cross_validator, %{chain_replication_nodes: _, beacon_replication_nodes: _}} =
             :sys.get_state(cross_validator_pid)
  end

  describe "cross_validate/2" do
    test "should cross validate the validation stamp and notify other node about it" do
      tx = Transaction.new(:node, %TransactionData{})

      {pub, _} = Crypto.generate_deterministic_keypair("seed3")

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: pub,
        first_public_key: pub,
        ready?: true,
        authorized?: true,
        available?: true,
        network_patch: "AAA",
        enrollment_date: DateTime.utc_now()
      })

      validation_nodes = Election.validation_nodes(tx)
      me = self()

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
            [
              {:error, :transaction_chain_not_exists},
              {:error, :unspent_output_transactions_not_exists}
            ]

          {:add_context, _, _, _, _, _, _} ->
            :ok

          [{:set_replication_trees, _, _, _}, {:cross_validate, _, stamp}] ->
            send(me, stamp)
            :ok

          {:cross_validation_done, _, stamp} ->
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
        ["key10", "key23"],
        <<1::1, 1::1>>,
        <<0::1, 1::1, 0::1>>,
        <<1::1, 1::1>>
      )

      Worker.add_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        ["key10", "key23"],
        <<1::1, 1::1>>,
        <<0::1, 1::1, 0::1>>,
        <<1::1, 1::1>>
      )

      {:wait_cross_validation_stamps, _} = :sys.get_state(coordinator_pid)

      receive do
        stamp = %ValidationStamp{} ->
          Worker.cross_validate(cross_validator_pid, stamp)

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
              stamp = {Crypto.sign_with_node_key(validation_stamp), [], Crypto.node_public_key()}
              Worker.add_cross_validation_stamp(coordinator_pid, stamp)

            Enum.any?(cross_validation_nodes, &(&1.last_public_key == pub)) ->
              stamp = {Crypto.sign(validation_stamp, priv), [], pub}
              Worker.add_cross_validation_stamp(coordinator_pid, stamp)

            Enum.any?(cross_validation_nodes, &(&1.last_public_key == pub3)) ->
              stamp = {Crypto.sign(validation_stamp, priv3), [], pub3}
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
          [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
            [
              {:error, :transaction_chain_not_exists},
              {:error, :unspent_output_transactions_not_exists}
            ]

          {:add_context, _, _, _, _, _, _} ->
            :ok

          [{:set_replication_trees, _, chain_tree, beacon_tree}, {:cross_validate, _, stamp}] ->
            send(me, {stamp, chain_tree, beacon_tree})
            :ok

          {:cross_validation_done, _, stamp} ->
            send(me, {:cross_validation_done, stamp})
            :ok

          {:replicate_address, _} ->
            send(me, :replicate_address)

          {:replicate_chain, _} ->
            send(me, :replication_chain)

          {:replicate_transaction, tx} ->
            send(me, {:replicate_transaction, tx})
        end
      end)

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

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "key10",
        first_public_key: "key10",
        ready?: true,
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
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        enrollment_date: DateTime.utc_now()
      })

      Worker.add_context(
        coordinator_pid,
        List.last(validation_nodes).last_public_key,
        ["key10", "key23"],
        <<1::1>>,
        <<0::1, 1::1, 0::1, 1::1>>,
        <<1::1, 1::1>>
      )

      {:wait_cross_validation_stamps, _} = :sys.get_state(coordinator_pid)

      receive do
        {stamp, chain_tree, beacon_tree} ->
          Worker.set_replication_trees(cross_validator_pid, chain_tree, beacon_tree)
          Worker.cross_validate(cross_validator_pid, stamp)

          receive do
            {:replicate_transaction, %Transaction{cross_validation_stamps: stamps}} ->
              assert length(stamps) == 1
          end

          Process.sleep(200)
          assert !Process.alive?(cross_validator_pid)
      end

      receive do
        {:cross_validation_done, _stamp} ->
          {_, %{validation_stamp: validation_stamp}} = :sys.get_state(coordinator_pid)

          if List.last(validation_nodes).last_public_key == Crypto.node_public_key() do
            stamp = {Crypto.sign_with_node_key(validation_stamp), [], Crypto.node_public_key()}
            Worker.add_cross_validation_stamp(coordinator_pid, stamp)
          else
            {pub, priv} = Crypto.generate_deterministic_keypair("seed")
            stamp = {Crypto.sign(validation_stamp, priv), [], pub}
            Worker.add_cross_validation_stamp(coordinator_pid, stamp)
          end

          Process.sleep(200)
          assert !Process.alive?(coordinator_pid)

          {:messages, messages} = :erlang.process_info(me, :messages)

          receive do
            {:replicate_transaction, %Transaction{cross_validation_stamps: stamps}} ->
              assert length(stamps) == 1
          end

          assert Enum.any?(messages, &(&1 == :replicate_address))
      end
    end
  end
end
