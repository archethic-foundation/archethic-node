# defmodule UnirisElection.DefaultImpl.HypergeometricDistributionTest do
#   use ExUnit.Case
#   doctest UnirisElection.DefaultImpl.HypergeometricDistribution
#   use ExUnitProperties

#   property "run_simulation/1 is always < 200" do
#     check all(nb_nodes <- positive_integer()) do
#       assert UnirisElection.DefaultImpl.HypergeometricDistribution.run_simulation(nb_nodes) < 200
#     end
#   end
# end
