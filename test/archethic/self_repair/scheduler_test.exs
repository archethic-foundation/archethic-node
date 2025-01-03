defmodule Archethic.SelfRepair.SchedulerTest do
  use ArchethicCase, async: false

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetBeaconSummaries
  alias Archethic.P2P.Message.GetBeaconSummariesAggregate
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Node

  alias Archethic.BeaconChain.SummaryAggregate

  alias Archethic.SelfRepair.Scheduler
  alias Archethic.SelfRepair.Sync

  import Mox

  setup do
    :ok

    Application.put_env(:archethic, Archethic.BeaconChain.SummaryTimer, interval: "0 0 0 * * * *")
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

    Application.put_env(:archethic, Scheduler, interval: "*/3 * * * * * *")
    {:ok, pid} = Scheduler.start_link([], [])

    assert :ok = Scheduler.start_scheduler(pid)
    %{timer: timer} = :sys.get_state(pid)

    :erlang.trace(pid, true, [:receive])

    assert_receive {:trace, ^pid, :receive, :sync}, 4_000
    Process.cancel_timer(timer)
  end

  test "start_scheduler/1 should restart and send node_down if sync failed" do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-2, :day),
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now() |> DateTime.add(-2, :day)
    })

    MockClient
    |> expect(:send_message, fn _, %GetBeaconSummariesAggregate{}, _ ->
      {:error, :network_issue}
    end)
    |> expect(:send_message, fn _, %GetBeaconSummariesAggregate{}, _ ->
      {:ok, %SummaryAggregate{summary_time: DateTime.utc_now(), availability_adding_time: 1}}
    end)
    |> stub(:send_message, fn _, %GetBeaconSummaries{}, _ ->
      {:error, :network_issue}
    end)

    Application.put_env(:archethic, Scheduler, interval: "* * * * * * *")

    {:ok, pid} = Scheduler.start_link([], [])
    assert :ok = Scheduler.start_scheduler(pid)
    %{timer: timer} = :sys.get_state(pid)

    :erlang.trace(pid, true, [:receive])

    :persistent_term.put(:archethic_up, :up)
    Archethic.PubSub.register_to_node_status()

    assert_receive {:trace, ^pid, :receive, :sync}, 1_500
    assert_receive :node_down, 1_500
    assert_receive :node_up, 1_500
    Process.cancel_timer(timer)
  end

  test "handle_info/3 should initiate the loading of missing transactions, schedule the next repair and update the last sync date" do
    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ -> {:ok, %NotFound{}}
      _, %GetBeaconSummaries{}, _ -> {:error, :network_issue}
    end)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now() |> DateTime.add(-1, :day)
    })

    first_last_sync_date = Sync.last_sync_date()

    me = self()

    MockDB
    |> expect(:set_bootstrap_info, fn "last_sync_time", time ->
      send(me, {:last_sync_time, time |> String.to_integer() |> DateTime.from_unix!()})
      :ok
    end)

    Application.put_env(:archethic, Scheduler, interval: "0 0 * * * * *")

    {:ok, pid} = Scheduler.start_link([], [])

    send(pid, :sync)

    receive do
      {:last_sync_time, last_sync_date} ->
        assert DateTime.diff(last_sync_date, first_last_sync_date) > 0
    after
      200 -> :skip
    end
  end
end
