defmodule UnirisElection.DefaultImpl.HeuristicConstraints.Storage do
  @moduledoc false
  defstruct [:min_geo_patch, :min_geo_patch_avg_availability, :number_replicas]

  @type t :: %__MODULE__{
          min_geo_patch: (() -> non_neg_integer()),
          min_geo_patch_avg_availability: (() -> non_neg_integer()),
          number_replicas: (nonempty_list(UnirisP2P.Node.t()) -> non_neg_integer())
        }
end
