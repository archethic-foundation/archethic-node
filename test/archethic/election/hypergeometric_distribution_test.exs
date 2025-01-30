defmodule Archethic.Election.HypergeometricDistributionTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Archethic.Election.HypergeometricDistribution
  alias Archethic.Election.HypergeometricDistribution.SecurityParameters

  doctest HypergeometricDistribution

  # Constants
  @scaling_limit 200
  @min_nodes 10
  @max_overbooked_nodes 20
  # Maximum security parameters (for nodes >200)
  @max_malicious_rate 0.75
  @min_tolerance 1.0e-9
  @min_overbooking_rate 0.10
  # Minimum security parameters (for small networks)
  @min_malicious_rate 0.65
  @max_tolerance 1.0e-6
  @max_overbooking_rate 0.25

  describe "run_simulation/2" do
    property "required nodes is always <= 201" do
      storage_params = HypergeometricDistribution.get_storage_security_parameters()

      check all(nb_nodes <- StreamData.integer(1..100_000)) do
        assert HypergeometricDistribution.run_simulation(nb_nodes, storage_params) |> elem(0) <=
                 201

        params = HypergeometricDistribution.get_security_parameters(nb_nodes)
        assert HypergeometricDistribution.run_simulation(nb_nodes, params) |> elem(0) <= 201
      end
    end

    property "overbooked nodes is always < required nodes" do
      check all(nb_nodes <- StreamData.integer(1..10000)) do
        params = HypergeometricDistribution.get_security_parameters(nb_nodes)

        {required_nodes, overbooked_nodes} =
          HypergeometricDistribution.run_simulation(nb_nodes, params)

        assert overbooked_nodes < required_nodes
      end
    end

    property "overbooked nodes is always <= #{@max_overbooked_nodes}" do
      check all(nb_nodes <- StreamData.integer(1..10000)) do
        params = HypergeometricDistribution.get_security_parameters(nb_nodes)

        assert HypergeometricDistribution.run_simulation(nb_nodes, params) |> elem(1) <=
                 @max_overbooked_nodes
      end
    end
  end

  describe "get_security_parameters/1" do
    property "should stay at minimum until #{@min_nodes} nodes" do
      check all(nb_nodes <- StreamData.integer(1..@min_nodes)) do
        %SecurityParameters{
          malicious_rate: malicious_rate,
          tolerance: tolerance,
          overbooking_rate: overbooking_rate
        } = HypergeometricDistribution.get_security_parameters(nb_nodes)

        assert malicious_rate == @min_malicious_rate
        assert tolerance == @max_tolerance
        assert overbooking_rate == @max_overbooking_rate
      end
    end

    property "should scale until #{@scaling_limit} nodes" do
      range = (@min_nodes + 2)..(@scaling_limit - 1)

      check all(nb_nodes <- StreamData.integer(range)) do
        %SecurityParameters{
          malicious_rate: malicious_rate,
          tolerance: tolerance,
          overbooking_rate: overbooking_rate
        } = HypergeometricDistribution.get_security_parameters(nb_nodes)

        assert malicious_rate > @min_malicious_rate and malicious_rate < @max_malicious_rate
        assert tolerance < @max_tolerance and tolerance > @min_tolerance

        assert overbooking_rate < @max_overbooking_rate and
                 overbooking_rate > @min_overbooking_rate
      end
    end

    property "should at maximum over #{@scaling_limit} nodes" do
      check all(nb_nodes <- StreamData.integer(@scaling_limit..(@scaling_limit * 100))) do
        %SecurityParameters{
          malicious_rate: malicious_rate,
          tolerance: tolerance,
          overbooking_rate: overbooking_rate
        } = HypergeometricDistribution.get_security_parameters(nb_nodes)

        assert malicious_rate == @max_malicious_rate
        assert tolerance == @min_tolerance
        assert overbooking_rate == @min_overbooking_rate
      end
    end
  end
end
