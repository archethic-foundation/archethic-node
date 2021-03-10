defmodule Uniris.SharedSecrets.NodeRenewalSchedulerTest do
  use UnirisCase, async: false

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.BeaconChain.SubsetRegistry

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Message.StartMining
  alias Uniris.P2P.Node

  alias Uniris.SharedSecrets.NodeRenewalScheduler, as: Scheduler

  import Mox

  setup do
    start_supervised!({BeaconSlotTimer, interval: "* * * * * *"})
    Enum.each(BeaconChain.list_subsets(), &Registry.register(SubsetRegistry, &1, []))
    start_supervised!(Batcher)
    :ok
  end

  describe "start_link/1" do
    test "should initiate the node renewal scheduler and trigger node renewal every each seconds" do
      P2P.add_node(%Node{
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        average_availability: 1.0
      })

      me = self()

      MockClient
      |> stub(:send_message, fn
        _, %BatchRequests{requests: [%StartMining{}]}, _ ->
          send(me, :renewal_processed)
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
      end)

      assert {:ok, pid} = Scheduler.start_link([interval: "*/2 * * * * *"], [])
      Scheduler.start_scheduling(pid)

      assert %{interval: "*/2 * * * * *"} = :sys.get_state(pid)

      assert_receive :renewal_processed, 3_000
    end
  end
end
