defmodule Uniris.SharedSecrets.NodeRenewalSchedulerTest do
  use UnirisCase, async: false

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.StartMining
  alias Uniris.P2P.Node

  alias Uniris.SharedSecrets.NodeRenewalScheduler, as: Scheduler

  import Mox

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

      MockTransport
      |> stub(:send_message, fn _, _, %StartMining{} ->
        send(me, :renewal_processed)
        {:ok, :ok}
      end)

      assert {:ok, pid} = Scheduler.start_link([interval: "*/2 * * * * *", trigger_offset: 1], [])

      assert %{interval: "*/2 * * * * *", trigger_offset: 1} = :sys.get_state(pid)

      assert_receive :renewal_processed, 3_000
    end
  end
end
