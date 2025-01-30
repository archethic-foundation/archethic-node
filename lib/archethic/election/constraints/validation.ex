defmodule Archethic.Election.ValidationConstraints do
  @moduledoc """
  Represents the constraints for the validation nodes election
  """

  @default_min_validation_geo_patch 3

  defstruct [
    :min_geo_patch,
    :validation_numbers
  ]

  alias Archethic.Election.HypergeometricDistribution

  @typedoc """
  Each validation constraints represent a function which will be executed during the election algorithms:
  - min_geo_patch: Require number of distinct geographic patch for the elected validation nodes.
  This property ensure the geographical security of the transaction validation by spliting
  the computation in many place on the world.
  - validation_numbers: Required number of validation nodes for a given transaction and the allowed
  number of overboking nodes
  """
  @type t :: %__MODULE__{
          min_geo_patch: (() -> non_neg_integer()),
          validation_numbers: (pos_integer() -> {non_neg_integer(), non_neg_integer()})
        }

  def new(
        min_geo_patch_fun \\ &min_geo_patch/0,
        validation_number_fun \\ &hypergeometric_distribution/1
      ) do
    %__MODULE__{
      min_geo_patch: min_geo_patch_fun,
      validation_numbers: validation_number_fun
    }
  end

  @doc """
  Determine the minimum of geo patch to cover
  """
  @spec min_geo_patch :: non_neg_integer()
  def min_geo_patch, do: @default_min_validation_geo_patch

  @doc """
  Run a simulation of the hypergeometric distribution based on a number of nodes
  """
  @spec hypergeometric_distribution(nb_nodes :: pos_integer()) :: pos_integer()
  def hypergeometric_distribution(nb_nodes) when nb_nodes > 0 do
    security_paramters = HypergeometricDistribution.get_security_parameters(nb_nodes)
    HypergeometricDistribution.run_simulation(nb_nodes, security_paramters)
  end
end
