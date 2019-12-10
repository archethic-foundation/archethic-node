defmodule UnirisChain.Transaction.ValidationStamp do
  @moduledoc """
  Represents a validation stamp created by a coordinator on a pending transaction
  """

  @enforce_keys [:proof_of_integrity, :proof_of_work, :signature]
  defstruct [
    :proof_of_integrity,
    :proof_of_work,
    :signature
  ]

  @typedoc """
  Validation performed by a coordinator:
  - Proof of work: results of the verification from the list of origin public keys matching the origin signature
  - Proof of integrity: Integry proof of the entire transaction chain
  - Signature: generated from the coordinator private key to avoid non-repudidation of the stamp
  """
  @type t :: %__MODULE__{
          proof_of_integrity: binary(),
          proof_of_work: binary(),
          signature: binary()
        }
end
