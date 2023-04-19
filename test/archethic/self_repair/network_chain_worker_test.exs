defmodule Archethic.SelfRepair.NetworkChainWorkerTest do
  # Cannot be async because it depends on global RepairWorker
  use ArchethicCase, async: false

  import ArchethicCase

  alias Archethic.BeaconChain.SummaryTimer
  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.SelfRepair.NetworkChainWorker

  import Mox

  describe "Worker FSM" do
    setup do
      start_supervised!({SummaryTimer, Application.get_env(:archethic, SummaryTimer)})

      OracleChain.MemTable.put_addr(random_address(), DateTime.utc_now())

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })
    end

    test "should be able to concurrently call the same sync" do
      MockDB
      |> expect(:get_last_chain_address, fn address ->
        {address, DateTime.utc_now()}
      end)

      # even if we call the resync multiple times
      # the above expect tell us that only one sync is running
      :ok = NetworkChainWorker.resync(:oracle)
      :ok = NetworkChainWorker.resync(:oracle)
      :ok = NetworkChainWorker.resync(:oracle)
      :ok = NetworkChainWorker.resync(:oracle)

      # this sleep is necessary for the worker to start the task
      Process.sleep(10)
    end
  end
end
