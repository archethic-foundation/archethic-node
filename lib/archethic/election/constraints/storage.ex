defmodule Archethic.Election.StorageConstraints do
  @moduledoc """
  Represents the constraints for the storage nodes election
  """

  defstruct [
    :min_geo_patch,
    :min_geo_patch_average_availability,
    :number_replicas
  ]

  alias Archethic.Election.HypergeometricDistribution

  alias Archethic.P2P.Node

  @default_min_geo_patch 4
  @default_min_geo_patch_avg_availability 0.8

  @type min_geo_patch_fun() :: (() -> non_neg_integer())
  @type min_geo_patch_avg_availability_fun() :: (() -> float())
  @type number_replicas_fun() :: (nonempty_list(Node.t()) -> non_neg_integer())

  @typedoc """
  Each storage constraints represent a function which will be executed during the election algorithms:
  - min_storage_geo_patch: Require number of distinct geographic patch for the elected storage nodes.
  This property ensure the geographical security of the sharding by splitting in
  many place on the world.
  It aims to support disaster recovery
  - min_storage_geo_patch_avg_availability: Require number of average availability by distinct geographical patches.
  This property ensures than each patch of the sharding will support a certain availability
  from these nodes.
  - number_replicas: Require number of storages nodes for a given list of nodes according to their
  availability. 
  """
  @type t :: %__MODULE__{
          min_geo_patch: min_geo_patch_fun(),
          min_geo_patch_average_availability: min_geo_patch_avg_availability_fun(),
          number_replicas: number_replicas_fun()
        }

  @spec new(min_geo_patch_fun(), min_geo_patch_avg_availability_fun(), number_replicas_fun()) ::
          __MODULE__.t()
  def new(
        min_geo_patch_fun \\ &min_geo_patch/0,
        min_geo_patch_avg_availability_fun \\ &min_geo_patch_avg_availability/0,
        number_replicas_fun \\ &hypergeometric_distribution/1
      )
      when is_function(min_geo_patch_fun) and is_function(min_geo_patch_avg_availability_fun) and
             is_function(number_replicas_fun) do
    %__MODULE__{
      min_geo_patch: min_geo_patch_fun,
      min_geo_patch_average_availability: min_geo_patch_avg_availability_fun,
      number_replicas: number_replicas_fun
    }
  end

  defp min_geo_patch, do: @default_min_geo_patch

  defp min_geo_patch_avg_availability, do: @default_min_geo_patch_avg_availability

  @doc """
  Give a number of replicas using the `2^(log10(n)+5)` to support maximum data availability, cumulative average availability.

  Starting from 143 nodes the number replicas start to reduce from the total number of nodes.

  ## Examples

      iex> node_list = Enum.map(1..50, fn _ -> %Node{average_availability: 1} end)
      ...> StorageConstraints.number_replicas_by_2log10(node_list)
      50

      iex> node_list = Enum.map(1..200, fn _ -> %Node{average_availability: 1} end)
      ...> StorageConstraints.number_replicas_by_2log10(node_list)
      158
  """
  @spec number_replicas_by_2log10(list(Node.t()), (list(Node.t()) -> float())) :: pos_integer()
  def number_replicas_by_2log10(
        nodes,
        formula_threshold_sum_availability \\ fn nb_nodes ->
          Float.round(:math.pow(2, :math.log10(nb_nodes) + 5))
        end
      )
      when is_list(nodes) and length(nodes) >= 1 do
    nb_nodes = length(nodes)
    threshold_sum_availability = formula_threshold_sum_availability.(nb_nodes)

    Enum.reduce_while(nodes, %{sum_average_availability: 0, nb: 0}, fn %Node{
                                                                         average_availability:
                                                                           avg_availability
                                                                       },
                                                                       acc ->
      if acc.sum_average_availability >= threshold_sum_availability do
        {:halt, acc}
      else
        {
          :cont,
          acc
          |> Map.update!(:nb, &(&1 + 1))
          |> Map.update!(:sum_average_availability, &(&1 + avg_availability))
        }
      end
    end)
    |> Map.get(:nb)
  end

  @doc """
  Run a simulation of the hypergeometric distribution based on a number of nodes
  """
  @spec hypergeometric_distribution(list(Node.t())) :: pos_integer()
  def hypergeometric_distribution(nodes) when is_list(nodes) and length(nodes) >= 0 do
    nodes
    |> length()
    |> HypergeometricDistribution.run_simulation()
  end
end
