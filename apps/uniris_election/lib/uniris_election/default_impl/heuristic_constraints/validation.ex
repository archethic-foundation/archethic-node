defmodule UnirisElection.DefaultImpl.HeuristicConstraints.Validation do
  @moduledoc false
  defstruct [:min_geo_patch, :validation_number]

  @type t :: %__MODULE__{
          min_geo_patch: (() -> non_neg_integer()),
          validation_number: (UnirisChain.Transaction.pending() -> non_neg_integer())
        }
end
