defmodule UnirisCore.Election.ValidationConstraints do
  @moduledoc """
  Represents the constraints for the validation nodes election
  """
  defstruct [:min_geo_patch, :min_validation_number, :validation_number]

  @type min_geo_patch_fun :: (() -> non_neg_integer())
  @type validation_number_fun :: (UnirisCore.Transaction.pending() -> non_neg_integer())

  @type t :: %__MODULE__{
          min_geo_patch: min_geo_patch_fun(),
          min_validation_number: non_neg_integer(),
          validation_number: validation_number_fun()
        }
end
