defmodule Archethic.Metrics.CollectorTest do
  use ExUnit.Case

  import Mox

  alias Archethic.Metrics.Collector

  setup :set_mox_global
  setup :verify_on_exit!

  describe "retrive_network_metrics/1" do
    test "should fetch and aggregate metrics" do
      MockMetricsCollector
      |> stub(:fetch_metrics, fn _ ->
        {:ok,
         """
         # HELP archethic_mining_full_transaction_validation_duration
         # TYPE archethic_mining_full_transaction_validation_duration histogram
         archethic_mining_full_transaction_validation_duration_sum 9
         archethic_mining_full_transaction_validation_duration_count 50
         """}
      end)

      assert %{
               "nb_transactions" => 50,
               "archethic_mining_full_transaction_validation_duration" => 0.18
             } =
               Collector.retrieve_network_metrics([{127, 0, 0, 1}, {127, 0, 0, 1}, {127, 0, 0, 1}])
    end
  end
end
