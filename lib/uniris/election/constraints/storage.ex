defmodule Uniris.Election.StorageConstraints do
  @moduledoc """
  Represents the constraints for the storage nodes election
  """

  defstruct [:min_geo_patch, :min_geo_patch_avg_availability, :number_replicas]

  @type min_geo_patch_fun() :: (() -> non_neg_integer())
  @type min_geo_patch_avg_availability_fun() :: (() -> non_neg_integer())
  @type number_replicas_fun() :: (nonempty_list(Uniris.P2P.Node.t()) -> non_neg_integer())

  @type t :: %__MODULE__{
          min_geo_patch: min_geo_patch_fun,
          min_geo_patch_avg_availability: min_geo_patch_avg_availability_fun,
          number_replicas: number_replicas_fun
        }
end
