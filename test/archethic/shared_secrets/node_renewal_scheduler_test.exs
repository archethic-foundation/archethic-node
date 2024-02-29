defmodule Archethic.SharedSecrets.NodeRenewalSchedulerTest do
  use ArchethicCase, async: false

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.SubsetRegistry

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.StartMining
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.Scheduler, as: SelfRepairScheduler

  alias Archethic.SharedSecrets.NodeRenewalScheduler, as: Scheduler

  alias Archethic.TransactionChain.Transaction

  import ArchethicCase, only: [setup_before_send_tx: 0]

  import Mox

  setup do
    SelfRepairScheduler.start_link([interval: "0 0 0 * *"], [])
    Enum.each(BeaconChain.list_subsets(), &Registry.register(SubsetRegistry, &1, []))

    setup_before_send_tx()

    :ok
  end

  test "should initiate the node renewal scheduler and trigger node renewal every each seconds" do
    :persistent_term.put(:archethic_up, :up)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      average_availability: 1.0
    })

    me = self()

    MockClient
    |> stub(:send_message, fn _, %StartMining{}, _ ->
      send(me, :renewal_processed)
      {:ok, %Ok{}}
    end)

    MockDB
    |> expect(:get_latest_tps, fn -> 10.0 end)

    assert {:ok, pid} = Scheduler.start_link([interval: "*/2 * * * * *"], [])

    assert {:scheduled, %{interval: "*/2 * * * * *"}} = :sys.get_state(pid)

    send(
      pid,
      {:node_update,
       %Node{
         authorized?: true,
         available?: true,
         first_public_key: Crypto.first_node_public_key()
       }}
    )

    assert_receive :renewal_processed, 3_000
    :persistent_term.put(:archethic_up, nil)
  end

  test "should retrigger the scheduling after tx replication" do
    :persistent_term.put(:archethic_up, :up)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      average_availability: 1.0
    })

    me = self()

    MockClient
    |> stub(:send_message, fn _,
                              %StartMining{transaction: %Transaction{address: tx_address}},
                              _ ->
      send(me, {:renewal_processed, tx_address})
      {:ok, %Ok{}}
    end)

    MockDB
    |> expect(:get_latest_tps, fn -> 10.0 end)

    assert {:ok, pid} = Scheduler.start_link([interval: "*/2 * * * * *"], [])

    assert {:scheduled, %{interval: "*/2 * * * * *", timer: timer1}} = :sys.get_state(pid)

    assert_receive {:renewal_processed, tx_address}, 3_000
    assert {:triggered, _} = :sys.get_state(pid)

    send(pid, {:new_transaction, tx_address, :node_shared_secrets, DateTime.utc_now()})
    assert {:scheduled, %{timer: timer2}} = :sys.get_state(pid)

    assert timer2 != timer1
    :persistent_term.put(:archethic_up, nil)
  end

  describe "Scheduler Behavior During start" do
    test "should be idle when node has not done Bootstrapping" do
      :persistent_term.put(:archethic_up, nil)

      assert {:ok, pid} = Scheduler.start_link([interval: "*/2 * * * * *"], [])

      assert {:idle, %{interval: "*/2 * * * * *"}} = :sys.get_state(pid)
    end

    test "should wait for node up message to start the scheduler, node: not authorized and available" do
      :persistent_term.put(:archethic_up, nil)

      assert {:ok, pid} = Scheduler.start_link([interval: "*/3 * * * * *"], [])

      assert {:idle, %{interval: "*/3 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:idle,
              %{
                interval: "*/3 * * * * *"
              }} = :sys.get_state(pid)
    end

    test "should wait for node up message to start the scheduler, node: authorized and available" do
      :persistent_term.put(:archethic_up, nil)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      assert {:ok, pid} = Scheduler.start_link([interval: "*/4 * * * * *"], [])

      assert {:idle, %{interval: "*/4 * * * * *"}} = :sys.get_state(pid)
      send(pid, :node_up)

      assert {:scheduled,
              %{
                interval: "*/4 * * * * *",
                index: _
              }} = :sys.get_state(pid)
    end

    test "should wait for node down message to stop the scheduler" do
      :persistent_term.put(:archethic_up, nil)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      assert {:ok, pid} = Scheduler.start_link([interval: "*/4 * * * * *"], [])

      assert {:idle, %{interval: "*/4 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:scheduled,
              %{
                interval: "*/4 * * * * *",
                index: _
              }} = :sys.get_state(pid)

      send(pid, :node_down)

      refute match?({:scheduled, _}, :sys.get_state(pid))
      refute match?({:idle, %{timer: _}}, :sys.get_state(pid))

      assert {:idle,
              %{
                interval: "*/4 * * * * *"
              }} = :sys.get_state(pid)
    end

    test "Should use persistent_term :archethic_up when a Scheduler crashes,current node: Not authorized and available" do
      :persistent_term.put(:archethic_up, :up)

      assert {:ok, pid} = Scheduler.start_link([interval: "*/5 * * * * *"], [])

      assert {:idle,
              %{
                interval: "*/5 * * * * *"
              }} = :sys.get_state(pid)

      :persistent_term.put(:archethic_up, nil)
    end

    test "Should use persistent_term :archethic_up when a Scheduler crashes, current node: authorized and available" do
      :persistent_term.put(:archethic_up, :up)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      assert {:ok, pid} = Scheduler.start_link([interval: "*/6 * * * * *"], [])

      assert {:scheduled,
              %{
                interval: "*/6 * * * * *",
                index: _
              }} = :sys.get_state(pid)

      :persistent_term.put(:archethic_up, nil)
    end
  end
end
