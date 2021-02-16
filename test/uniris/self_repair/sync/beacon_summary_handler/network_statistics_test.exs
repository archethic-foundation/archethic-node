defmodule Uniris.SelfRepair.Sync.BeaconSummaryHandler.NetworkStatisticsTest do
  use ExUnit.Case, async: false

  alias Uniris.SelfRepair.Sync.BeaconSummaryHandler.NetworkStatistics
  alias Uniris.Utils

  doctest NetworkStatistics

  setup do
    Path.wildcard(Utils.mut_dir("priv/p2p/network_stats*")) |> Enum.each(&File.rm_rf!/1)
    :ok
  end

  describe "start_link/1" do
    test "should initiate ETS table when no previous dump" do
      {:ok, _} = NetworkStatistics.start_link()
      assert [] = :ets.tab2list(:uniris_tps)
      assert [] = :ets.tab2list(:uniris_stats)
    end

    test "should start ETS table by loading the NetworkStatistics from the synchronization file" do
      {:ok, pid} = NetworkStatistics.start_link()

      NetworkStatistics.register_tps(DateTime.utc_now(), 100.0, 10_000)
      NetworkStatistics.increment_number_transactions()

      Process.exit(pid, :normal)

      Process.sleep(100)

      {:ok, _pid} = NetworkStatistics.start_link()
      assert [{_, 100.0, 10_000}] = :ets.tab2list(:uniris_tps)
    end
  end
end
