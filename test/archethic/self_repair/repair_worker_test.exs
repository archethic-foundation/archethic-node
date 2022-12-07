defmodule Archethic.SelfRepair.RepairWorkerTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Client.DefaultImpl
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetNextAddresses
  alias Archethic.P2P.Message.GetTransaction

  alias Archethic.SelfRepair.RepairWorker

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  import Mox

  setup do
    start_supervised!({SummaryTimer, interval: "0 0 * * *"})

    :ok
  end

  test "start_link/1 should start a new worker and create a task to replicate transaction" do
    {:ok, pid} =
      RepairWorker.start_link(
        first_address: "Alice1",
        storage_address: "Alice2",
        io_addresses: ["Bob1"]
      )

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
      RepairWorker.start_link(
        first_address: "Alice1",
        storage_address: "Alice2",
        io_addresses: ["Bob1", "Bob2"]
      )

    me = self()

    MockDB
    |> stub(:transaction_exists?, fn
      "Bob2", _ ->
        send(me, :exists_bob3)
        true

      _, _ ->
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
    |> stub(:transaction_exists?, fn _, _ -> Process.sleep(100) end)

    {:ok, pid} =
      RepairWorker.start_link(
        first_address: "Alice1",
        storage_address: "Alice2",
        io_addresses: ["Bob1", "Bob2"]
      )

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

  test "update_last_address/1 should request missing addresses and add them in DB" do
    node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      authorized?: true,
      authorization_date: ~U[2022-11-27 00:00:00Z],
      available?: true,
      availability_history: <<1::1>>
    }

    me = self()

    MockDB
    |> expect(:get_last_chain_address, fn "Alice2" -> {"Alice2", ~U[2022-11-27 00:10:00Z]} end)
    |> expect(:get_transaction, fn "Alice2", _ ->
      {:ok, %Transaction{validation_stamp: %ValidationStamp{timestamp: ~U[2022-11-27 00:10:00Z]}}}
    end)
    |> expect(:get_first_chain_address, 2, fn "Alice2" -> "Alice0" end)
    |> expect(:list_chain_addresses, fn "Alice0" ->
      [
        {"Alice1", ~U[2022-11-27 00:09:00Z]},
        {"Alice2", ~U[2022-11-27 00:10:00Z]},
        {"Alice3", ~U[2022-11-27 00:11:00Z]},
        {"Alice4", ~U[2022-11-27 00:12:00Z]}
      ]
    end)
    |> expect(:add_last_transaction_address, 2, fn
      "Alice0", "Alice3", ~U[2022-11-27 00:11:00Z] ->
        send(me, :add_alice3)

      "Alice0", "Alice4", ~U[2022-11-27 00:12:00Z] ->
        send(me, :add_alice4)
    end)

    MockClient
    |> expect(:send_message, fn node, msg = %GetNextAddresses{address: "Alice2"}, timeout ->
      send(me, :get_next_addresses)
      DefaultImpl.send_message(node, msg, timeout)
    end)

    RepairWorker.update_last_address("Alice2", [node])

    assert_receive :get_next_addresses
    assert_receive :add_alice3
    assert_receive :add_alice4
  end
end
