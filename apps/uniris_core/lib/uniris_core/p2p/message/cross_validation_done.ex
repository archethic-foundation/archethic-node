defmodule UnirisCore.P2P.Message.CrossValidationDone do
  @enforce_keys [:address, :cross_validation_stamp]
  defstruct [:address, :cross_validation_stamp]

  alias UnirisCore.Crypto
  alias UnirisCore.Transaction.CrossValidationStamp

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          cross_validation_stamp: CrossValidationStamp.t()
        }
end
