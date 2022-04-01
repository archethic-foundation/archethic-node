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
    {alice, bob} = TPSHelper.preliminaries()

    TPSHelper.withdraw_uco_via_host(alice.address, host, port, _amount = 100)
    TPSHelper.withdraw_uco_via_host(bob.address, host, port, _amount = 100)

    scenario = %{
      "tps" => fn nb_of_txns ->
        benchmark(alice, bob, host, port, nb_of_txns)
      end
    }

    {scenario,
     [
       inputs: %{
         "100 transactions" => Enum.to_list(1..100)
         #  "1000 transactions" => Enum.to_list(1..1_000),
         #  "2000 transactions" => Enum.to_list(1..2_000)
         #  "10_000 transactions" => Enum.to_list(1..10_000)
         #  error after 100 txns
         #  /opt/app/releases/0.13.1/libexec/erts.sh: line 66:   153 Killed                  "$__erl" -boot_var ERTS_LIB_DIR "$RELEASE_ROOT_DIR/lib" -boot "${RELEASE_ROOT_DIR}/bin/start_clean" ${SYS_CONFIG_PATH:+-config "${SYS_CONFIG_PATH}"} -pa "${CONSOLIDATED_DIR}" ${EXTRA_CODE_PATHS:+-pa "${EXTRA_CODE_PATHS}"} "$@"
         #  "100_000 transactions" => Enum.to_list(1..100_000),
         #  "1_000_000 transactions" => Enum.to_list(1..1_000_0000)
       },
       print: [benchmarking: true]
     ]}
  end

  def benchmark(alice, bob, host, port, nb_of_txns) do
    Task.async_stream(
      nb_of_txns,
      fn x ->
        Logger.debug("tps========================= loaded  #{inspect(x)}")
        TPSHelper.dispatch_transactions(alice, bob, host, port)
      end,
      max_concurrenct: System.schedulers_online() * 100
    )
  end
end
