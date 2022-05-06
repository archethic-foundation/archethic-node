defmodule Archethic.SelfRepair.SchedulerTest do
  use ArchethicCase, async: false

  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.SummaryTimer, as: BeaconSummaryTimer

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.Scheduler
  alias Archethic.SelfRepair.Sync

  import Mox

  setup do
    start_supervised!({BeaconSummaryTimer, interval: "0 0 0 * * * *"})
    start_supervised!({BeaconSlotTimer, interval: "0 0 * * * * *"})
    :ok
  end

  test "start_scheduler/1 should start the self repair timer" do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now() |> DateTime.add(-1)
    })

    MockClient
    |> stub(:send_message, fn _, %GetTransaction{}, _ ->
      {:ok, %NotFound{}}
    end)

    {:ok, pid} = Scheduler.start_link([interval: "*/1 * * * * * *"], [])
    assert :ok = Scheduler.start_scheduler(pid)

    :erlang.trace(pid, true, [:receive])

    assert_receive {:trace, ^pid, :receive, :sync}, 2_000

    Process.sleep(100)
  end

  test "handle_info/3 should initiate the loading of missing transactions, schedule the next repair and update the last sync date" do
    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}
    end)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now() |> DateTime.add(-1)
    })

    first_last_sync_date = Sync.last_sync_date()

    me = self()

    MockDB
    |> stub(:set_bootstrap_info, fn "last_sync_time", time ->
      send(me, {:last_sync_time, time |> String.to_integer() |> DateTime.from_unix!()})
      :ok
    end)

    {:ok, pid} = Scheduler.start_link([interval: "*/1 * * * * * *"], [])

    send(pid, :sync)

    receive do
      {:last_sync_time, last_sync_date} ->
        assert DateTime.diff(last_sync_date, first_last_sync_date) > 0
    end
  end
end
