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
    Logger.debug("tps========================= host  #{inspect(host)}")

    port = Application.get_env(:archethic, ArchEthic.P2P.Listener)[:port]

    Logger.debug("tps========================= host  #{inspect(port)}")

    {alice, bob} = TPSHelper.preliminaries()

    TPSHelper.withdraw_uco_via_host(alice.address, host, port)
    TPSHelper.withdraw_uco_via_host(bob.address, host, port)

    scenario = %{
      "tps" => fn ->
        benchmark(alice, bob, host, port)
      end
    }

    {scenario, [print: [benchmarking: true]]}
  end

  def benchmark(alice, bob, host, port) do
    Task.async_stream(
      1..100,
      fn x ->
        Logger.debug("tps========================= loaded  #{inspect(x)}")
        TPSHelper.dispatch_transactions(alice, bob, host, port)
      end,
      max_concurrenct: System.schedulers_online() * 10
    )
  end
end
