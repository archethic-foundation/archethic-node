defmodule Archethic.Election.ValidationConstraintsTest do
  use ArchethicCase
  use ExUnitProperties

  alias Archethic.Election.ValidationConstraints
  alias Archethic.Election.HypergeometricDistribution

  doctest ValidationConstraints

  property "validation_number matches hypergeometric distribution" do
    check all(nb_nodes <- StreamData.integer(1..200)) do
      security_parameters = HypergeometricDistribution.get_security_parameters(nb_nodes)

      expected = HypergeometricDistribution.run_simulation(nb_nodes, security_parameters)
      constraints = ValidationConstraints.new()
      actual = constraints.validation_numbers.(nb_nodes)

      assert actual == expected
    end
  end
end
