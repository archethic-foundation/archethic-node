defmodule Archethic.Metrics.CollectorTest do
  use ExUnit.Case

  import Mox

  alias Archethic.Metrics.Collector

  setup :set_mox_global
  setup :verify_on_exit!

  describe "fetch_metrics/2" do
    test "should fetch and aggregate metrics" do
      MockMetricsCollector
      |> stub(:fetch_metrics, fn _, _ ->
        {:ok,
         """
         # HELP archethic_mining_full_transaction_validation_duration
         # TYPE archethic_mining_full_transaction_validation_duration histogram
         archethic_mining_full_transaction_validation_duration_sum 9
         archethic_mining_full_transaction_validation_duration_count 50
         """}
      end)

      assert {:ok,
              %{
                "archethic_mining_full_transaction_validation_duration" => %{count: 50, sum: 9.0}
              }} = Collector.fetch_metrics({127, 0, 0, 1}, 4000)
    end
  end
end
