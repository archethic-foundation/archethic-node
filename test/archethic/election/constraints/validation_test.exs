defmodule Archethic.Election.ValidationConstraintsTest do
  use ArchethicCase
  import ArchethicCase
  use ExUnitProperties

  alias Archethic.P2P.Node

  alias Archethic.Election.ValidationConstraints
  alias Archethic.Election.HypergeometricDistribution

  doctest ValidationConstraints

  property "validation_number matches hypergeometric distribution" do
    check all(nb_nodes <- StreamData.integer(1..200)) do
      nodes =
        for _ <- 1..nb_nodes do
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            first_public_key: random_public_key(),
            last_public_key: random_public_key(),
            authorized?: true,
            authorization_date: DateTime.utc_now() |> DateTime.add(-1)
          }
        end

      expected = HypergeometricDistribution.run_simulation(length(nodes))
      constraints = ValidationConstraints.new()
      actual = constraints.validation_number.(nodes)

      assert actual == expected
    end
  end
end
