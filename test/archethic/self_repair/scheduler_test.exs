defmodule ArchEthic.SelfRepair.SchedulerTest do
  use ArchEthicCase, async: false

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias ArchEthic.BeaconChain.Subset, as: BeaconSubset
  alias ArchEthic.BeaconChain.SummaryTimer, as: BeaconSummaryTimer

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Node

  alias ArchEthic.SelfRepair.Scheduler

  import Mox

  setup do
    start_supervised!({BeaconSummaryTimer, interval: "0 * * * * * *"})
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))
    :ok
  end

  test "start_scheduler/2 should start the self repair timer" do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    MockClient
    |> stub(:send_message, fn _, %GetTransaction{} ->
      {:ok, %NotFound{}}
    end)

    {:ok, pid} = Scheduler.start_link([interval: "*/1 * * * * * *"], [])
    assert :ok = Scheduler.start_scheduler(pid, DateTime.utc_now())

    :erlang.trace(pid, true, [:receive])

    assert_receive {:trace, ^pid, :receive, :sync}, 2_000

    Process.sleep(100)
  end

  test "handle_info/3 should initiate the loading of missing transactions, schedule the next repair and update the last sync date" do
    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{} ->
        {:ok, %NotFound{}}
    end)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    {:ok, pid} = Scheduler.start_link([interval: "*/1 * * * * * *"], [])

    first_last_sync_date = DateTime.utc_now()
    Scheduler.start_scheduler(pid, first_last_sync_date)

    :erlang.trace(pid, true, [:receive])

    assert_receive {:trace, ^pid, :receive, :sync}, 2_000

    %{last_sync_date: next_last_sync_date} = :sys.get_state(pid)

    assert DateTime.compare(next_last_sync_date, first_last_sync_date) == :gt
  end
end
