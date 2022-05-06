defmodule Archethic.SharedSecrets.NodeRenewalSchedulerTest do
  use ArchethicCase, async: false

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.SubsetRegistry

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.StartMining
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.Scheduler, as: SelfRepairScheduler

  alias Archethic.SharedSecrets.NodeRenewalScheduler, as: Scheduler

  import Mox

  setup do
    SelfRepairScheduler.start_link(interval: "0 0 0 * *")
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * *"})
    Enum.each(BeaconChain.list_subsets(), &Registry.register(SubsetRegistry, &1, []))
    :ok
  end

  describe "start_link/1" do
    test "should initiate the node renewal scheduler and trigger node renewal every each seconds" do
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

      assert %{interval: "*/2 * * * * *"} = :sys.get_state(pid)

      send(
        pid,
        {:node_update, %Node{authorized?: true, first_public_key: Crypto.first_node_public_key()}}
      )

      assert_receive :renewal_processed, 3_000
    end
  end
end
