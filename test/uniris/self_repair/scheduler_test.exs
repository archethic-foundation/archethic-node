defmodule Uniris.SelfRepair.SchedulerTest do
  use UnirisCase, async: false

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.BeaconChain.Subset, as: BeaconSubset

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.BeaconSlotList
  alias Uniris.P2P.Message.GetBeaconSlots
  alias Uniris.P2P.Node

  alias Uniris.SelfRepair.Scheduler

  import Mox

  setup do
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *", trigger_offset: 0})
    Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))
    :ok
  end

  test "start_scheduler/2 should start the self repair timer" do
    MockTransport
    |> stub(:send_message, fn
      _, _, %GetBeaconSlots{} ->
        {:ok, %BeaconSlotList{slots: []}}
    end)

    {:ok, pid} = Scheduler.start_link([interval: "*/1 * * * * * *"], [])
    assert :ok = Scheduler.start_scheduler(pid, "AAA")

    :erlang.trace(pid, true, [:receive])

    assert_receive {:trace, ^pid, :receive, :sync}, 2_000

    Process.sleep(100)
  end

  test "handle_info/3 should initiate the loading of missing transactions, schedule the next repair and update the last sync date" do
    MockTransport
    |> stub(:send_message, fn
      _, _, %GetBeaconSlots{} ->
        {:ok, %BeaconSlotList{slots: []}}
    end)

    P2P.add_node(%Node{
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    {:ok, pid} = Scheduler.start_link([interval: "*/1 * * * * * *"], [])
    %{last_sync_date: first_last_sync_date} = :sys.get_state(pid)

    Scheduler.start_scheduler(pid, "AAA")

    :erlang.trace(pid, true, [:receive])

    assert_receive {:trace, ^pid, :receive, :sync}, 2_000

    %{last_sync_date: next_last_sync_date} = :sys.get_state(pid)

    assert DateTime.compare(next_last_sync_date, first_last_sync_date) == :gt
  end
end
