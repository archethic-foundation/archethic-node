defmodule ArchEthic.Utils.Regression.Benchmark.TPS do
  @moduledoc """
  Module for regession testing the paralleing processing of transactions and
  benchmarking the parallel transaction processing capability of a node
  """

  require Logger

  alias ArchEthic.Utils.Regression.Benchmark
  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper

  @behaviour Benchmark

  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]
    parallel_txns = 200

    scenario = %{
      "tps" => fn {{sender_seed, transaction_data}, host, port} ->
        benchmark({{sender_seed, transaction_data}, host, port})
      end
    }

    inputs = %{
      "#{parallel_txns} transactions" => {host, port}
    }

    {scenario,
     [
       before_each: fn {host, port} -> TPSHelper.before_each_scenario_instance({host, port}) end,
       print: [benchmarking: true],
       parallel: 200,
       inputs: inputs
     ]}
  end

  # it sends one txn from send to reciever
  # It takes sender seed and reciever address to create a transaction
  def benchmark({{sender_seed, transaction_data}, host, port}) do
    TPSHelper.send_transaction({{sender_seed, transaction_data}, host, port})
  end
end
