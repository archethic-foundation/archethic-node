defmodule Archethic.SelfRepair.NetworkChainWorkerTest do
  # Cannot be async because it depends on global RepairWorker
  use ArchethicCase, async: false

  import ArchethicCase

  alias Archethic.BeaconChain.SummaryTimer
  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.NodeList
  alias Archethic.P2P.Message.ListNodes
  alias Archethic.P2P.Node
  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.NetworkChainWorker

  import Mox

  describe "fsm" do
    test "should return a task when " do
      # TODO
    end
  end

  describe "resync_network_chain (non-node)" do
    setup do
      start_supervised!({SummaryTimer, Application.get_env(:archethic, SummaryTimer)})

      Archethic.OracleChain.MemTable.put_addr(random_address(), DateTime.utc_now())

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })
    end

    test "should start a resync when remote /= local" do
      last_address = random_address()

      MockDB
      |> expect(:get_last_chain_address, fn address ->
        {address, DateTime.utc_now()}
      end)
      |> expect(:transaction_exists?, fn _, _ ->
        # we add a sleep here to be sure the RepairWorker is running for enough time
        # so the repair is still in progress when we assert it
        Process.sleep(:infinity)
        false
      end)

      MockClient
      |> expect(:send_message, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: last_address}}
      end)

      :ok = NetworkChainWorker.resync(:oracle, false)
      assert SelfRepair.repair_in_progress?(OracleChain.get_current_genesis_address())

      # this sleep is necessary to give time to the RepairWorker to start its task
      # without it, the expect above will fail once in a while
      Process.sleep(150)
    end

    test "should not start a resync when remote == local" do
      last_address = random_address()

      MockDB
      |> expect(:get_last_chain_address, fn _ ->
        {last_address, DateTime.utc_now()}
      end)
      |> expect_not(:transaction_exists?, fn _, _ ->
        true
      end)

      MockClient
      |> expect(:send_message, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: last_address}}
      end)

      :ok = NetworkChainWorker.resync(:oracle, false)
      refute SelfRepair.repair_in_progress?(OracleChain.get_current_genesis_address())
    end
  end

  describe "resync_network_chain (node)" do
    test "should start a resync when remote /= local" do
      start_supervised!({SummaryTimer, Application.get_env(:archethic, SummaryTimer)})

      remote_node_last_address = random_address()
      local_node_last_address = random_address()

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        last_address: local_node_last_address,
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        enrollment_date: DateTime.utc_now() |> DateTime.add(-1),
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      }

      P2P.add_and_connect_node(node)

      MockDB
      |> expect(:transaction_exists?, fn _, _ ->
        # we add a sleep here to be sure the RepairWorker is running for enough time
        # so the repair is still in progress when we assert it
        Process.sleep(:infinity)
        false
      end)

      MockClient
      |> expect(:send_message, fn _, %ListNodes{}, _ ->
        {:ok, %NodeList{nodes: [node]}}
      end)
      |> expect(:send_message, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: remote_node_last_address}}
      end)

      :ok = NetworkChainWorker.resync(:node, false)
      assert SelfRepair.repair_in_progress?(local_node_last_address)

      # this sleep is necessary to give time to the RepairWorker to start its task
      # without it, the expect above will fail once in a while
      Process.sleep(150)
    end
  end
end
