defmodule Uniris.Governance.TestnetTest do
  use ExUnit.Case

  alias Uniris.Governance.Git
  alias Uniris.Governance.Testnet

  alias Uniris.P2P.BootstrapingSeeds

  alias Uniris.Transaction
  alias Uniris.TransactionData

  import Mox

  setup do
    me = self()

    Application.put_env(:uniris, BootstrapingSeeds,
      seeds: "127.0.0.1:3002:00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"
    )

    BootstrapingSeeds.start_link([])

    MockCommandLogger
    |> stub(:write, fn data, _ ->
      IO.write("#{data}\n")
    end)

    MockTestnet
    |> stub(:deploy, fn _address, p2p_port, web_port, p2p_seeds ->
      send(me, {p2p_port, web_port, p2p_seeds})
      :ok
    end)

    :ok
  end

  test "ports/1 should return deterministically ports for a given transaction timestamp" do
    tx = %Transaction{
      address: "@CodeChanges1",
      type: :code_proposal,
      timestamp: ~U[2020-08-17 08:10:16.338088Z],
      data: %TransactionData{}
    }

    assert {11_296, 16_885} = Testnet.ports(tx)
  end

  @tag infrastructure: true
  test "deploy/1 should initiate testnet with P2P seeds and ports" do
    changes = ~S"""
    diff --git a/lib/uniris/self_repair.ex b/lib/uniris/self_repair.ex
    index 124088f..c3add90 100755
    --- a/lib/uniris/self_repair.ex
    +++ b/lib/uniris/self_repair.ex
    @@ -91,7 +91,7 @@ defmodule Uniris.SelfRepair do
               node_patch: node_patch
             }
           ) do
    -    Logger.info("Self-repair synchronization started from #{inspect(last_sync_date)}")
    +    Logger.info("Self-repair synchronization started at #{inspect(last_sync_date)}")
         synchronize(last_sync_date, node_patch)
         schedule_sync(Utils.time_offset(interval))
         {:noreply, Map.put(state, :last_sync_date, update_last_sync_date())}

    """

    tx = %Transaction{
      address: "@CodeChanges1",
      type: :code_proposal,
      timestamp: ~U[2020-08-17 08:10:16.338088Z],
      data: %TransactionData{
        content: """
        Description: My new change
        Changes:
        #{changes}
        """
      }
    }

    Testnet.deploy(tx)

    assert_received {11_296, 16_885,
                     "127.0.0.1:11296:00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"}

    Git.clean(tx.address)
  end
end
