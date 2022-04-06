defmodule ArchEthic.Utils.Regression.Benchmark.TPS3 do
  @moduledoc """
  none
  """

  alias ArchEthic.Utils.Regression.Benchmark
  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper
  @behaviour Benchmark

  def plan([_host | _nodes], _opts) do
    # port = Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]
    parallel_txns = 100

    scenario = %{
      "Internal: Parallel Single Txn" => fn {txn} ->
        benchmark(txn)
      end
    }

    inputs = %{
      "#{parallel_txns} Parallel transactions" => {0}
    }

    {scenario,
     [
       before_each: fn {_x} -> before_each_scenario_instance() end,
       print: [benchmarking: true],
       parallel: parallel_txns,
       inputs: inputs
     ]}
  end

  def benchmark(txn) do
    TPSHelper.deploy_txn(txn)
  end

  def before_each_scenario_instance() do
    {sender_seed, receiver_seed} = {TPSHelper.random_seed(), TPSHelper.random_seed()}

    sender_seed
    |> TPSHelper.get_genesis_address()
    |> TPSHelper.allocate_funds()

    recipient_address =
      receiver_seed
      |> TPSHelper.get_genesis_address()

    txn =
      sender_seed
      |> TPSHelper.get_transaction(recipient_address)

    {txn}
  end
end
