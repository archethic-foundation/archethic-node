defmodule UnirisCore.BeaconSubsets do
  @moduledoc false

  use Agent

  def start_link(subsets) do
    Agent.start(fn -> subsets end, name: __MODULE__)
  end

  def all() do
    Agent.get(__MODULE__, & &1)
  end
end
