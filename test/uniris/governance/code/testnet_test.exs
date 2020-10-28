defmodule Uniris.Governance.Code.TestNetTest do
  use ExUnit.Case

  # alias Uniris.Governance.Code.Git
  # alias Uniris.Governance.Code.Proposal, as: CodeProposal
  # alias Uniris.Governance.Code.TestNet

  # alias Uniris.P2P.BootstrappingSeeds

  # import Mox

  #  @tag infrastructure: true
  #  test "deploy_proposal/1 should initiate testnet with P2P seeds and ports" do
  #    me = self()
  #
  #    Application.put_env(:uniris, BootstrappingSeeds,
  #      seeds: "127.0.0.1:3002:00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"
  #    )
  #
  #    BootstrappingSeeds.start_link([])
  #
  #    MockTestNet
  #    |> stub(:deploy, fn _address, _version, p2p_port, web_port, p2p_seeds ->
  #      send(me, {p2p_port, web_port, p2p_seeds})
  #      :ok
  #    end)
  #
  #    changes = ~S"""
  #    diff --git a/lib/uniris/supervisor.ex b/lib/uniris/supervisor.ex
  #    index 124088f..c3add90 100755
  #    --- a/lib/uniris/supervisor.ex
  #    +++ b/lib/uniris/supervisor.ex
  #    @@ -91,7 +91,7 @@ defmodule Uniris.SelfRepair do
  #               node_patch: node_patch
  #             }
  #           ) do
  #    -    Logger.info("Self-repair synchronization started from #{inspect(last_sync_date)}")
  #    +    Logger.info("Self-repair synchronization started at #{inspect(last_sync_date)}")
  #         synchronize(last_sync_date, node_patch)
  #         schedule_sync(Utils.time_offset(interval))
  #         {:noreply, Map.put(state, :last_sync_date, update_last_sync_date())}
  #
  #    """
  #
  #    %CodeProposal{
  #      address: "@CodeChanges1",
  #      timestamp: ~U[2020-08-17 08:10:16.338088Z],
  #      description: "My new change",
  #      changes: changes
  #    }
  #    |> TestNet.deploy_proposal()
  #
  #    assert_received {11_296, 16_885,
  #                     "127.0.0.1:11296:00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"}
  #
  #    Git.clean("@CodeChanges1")
  #  end
end
