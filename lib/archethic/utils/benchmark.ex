defmodule ArchEthic.Benchmark do
  @moduledoc """
  Benchmark is executed on a testnet with [benchee](https://github.com/bencheeorg/benchee)
  to measure performance and stresstest archethic-node.
  """

  @doc """
  Given a list of nodes forming testnet and options return a tuple of benchmark
  scenario and options for it.
  """
  @callback plan([String.t()], Keyword.t()) :: {map(), Keyword.t()}
end
