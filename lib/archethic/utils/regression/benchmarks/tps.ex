defmodule ArchEthic.Utils.Regression.Benchmark.TPS do
  @moduledoc """
  Module for regession testing the paralleing processing of transactions and
  benchmarking the parallel transaction processing capability of a node
  """

  require Logger

  alias ArchEthic.Utils.Regression.Benchmark

  @behaviour Benchmark

  def plan([_host | _nodes], _opts) do
  end
end
