defmodule Archethic.SelfRepair.Notifier.RepairWorkerTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.ShardRepair

  alias Archethic.SelfRepair.Notifier.RepairWorker

  import Mox

  setup do
    start_supervised!({SummaryTimer, interval: "0 0 * * *"})

    :ok
  end

  test "start_link/1 should start a new worker and create a task to replicate transaction" do
    {:ok, pid} =
      RepairWorker.start_link(%ShardRepair{
        first_address: "Alice1",
        storage_address: "Alice2",
        io_addresses: ["Bob1"]
      })

    assert %{storage_addresses: [], io_addresses: ["Bob1"], task: _task_pid} = :sys.get_state(pid)
  end

  test "repair_task/3 replicate a transaction if it does not already exists" do
    P2P.add_and_connect_node(%Node{
      first_public_key: "node1",
      last_public_key: "node1",
      geo_patch: "AAA",
      authorized?: true,
      authorization_date: ~U[2022-11-27 00:00:00Z],
      available?: true
    })

    {:ok, pid} =
      RepairWorker.start_link(%ShardRepair{
        first_address: "Alice1",
        storage_address: "Alice2",
        io_addresses: ["Bob1", "Bob2"]
      })

    me = self()

    MockDB
    |> stub(:transaction_exists?, fn
      "Bob2" ->
        send(me, :exists_bob3)
        true

      _ ->
        false
    end)

    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{address: "Alice2"}, _ ->
        send(me, :get_tx_alice2)

      _, %GetTransaction{address: "Bob1"}, _ ->
        send(me, :get_tx_bob1)

      _, %GetTransaction{address: "Bob2"}, _ ->
        send(me, :get_tx_bob2)
    end)

    assert_receive :get_tx_alice2
    assert_receive :get_tx_bob1

    assert_receive :exists_bob3
    refute_receive :get_tx_bob2

    assert not Process.alive?(pid)
  end

  test "add_message/1 should add new addresses in GenServer state" do
    MockDB
    |> stub(:transaction_exists?, fn _ -> Process.sleep(100) end)

    {:ok, pid} =
      RepairWorker.start_link(%ShardRepair{
        first_address: "Alice1",
        storage_address: "Alice2",
        io_addresses: ["Bob1", "Bob2"]
      })

    assert %{
             storage_addresses: [],
             io_addresses: ["Bob1", "Bob2"],
             task: _task_pid
           } = :sys.get_state(pid)

    GenServer.cast(pid, {:add_address, "Alice4", ["Bob2", "Bob3"]})
    GenServer.cast(pid, {:add_address, "Alice3", []})
    GenServer.cast(pid, {:add_address, nil, ["Bob4"]})

    assert %{
             storage_addresses: ["Alice3", "Alice4"],
             io_addresses: ["Bob1", "Bob2", "Bob3", "Bob4"],
             task: _task_pid
           } = :sys.get_state(pid)
  end
end
