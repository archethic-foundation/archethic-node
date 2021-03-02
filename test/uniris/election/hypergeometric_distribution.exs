defmodule Uniris.Election.HypergeometricDistributionTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Uniris.Election.HypergeometricDistribution

  doctest HypergeometricDistribution

  property "run_simulation/1 is always < 200" do
    check all(nb_nodes <- positive_integer()) do
      assert HypergeometricDistribution.run_simulation(nb_nodes) < 200
    end
  end
end
