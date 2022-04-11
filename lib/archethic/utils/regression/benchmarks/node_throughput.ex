defmodule ArchEthic.Utils.Regression.NodeThroughput do
  @moduledoc """
  Using Publically exposed Api To Benchmark
  """

  # alias modules
  alias ArchEthic.Utils.Regression.Benchmark

  # behaviour
  @behaviour Benchmark

  @impl true

  def plan([host | _nodes], opts) do
    IO.inspect(host, label: "host var")
    IO.inspect(opts, label: "opts")
    IO.inspect(binding())
  end
end
