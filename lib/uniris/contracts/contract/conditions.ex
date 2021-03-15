defmodule Uniris.Contracts.Contract.Conditions do
  @moduledoc """
  Represents the smart contract conditions
  """

  defstruct [
    :transaction,
    :origin_family,
    :oracle,
    :inherit
  ]

  alias Uniris.SharedSecrets

  @typedoc """
  Smart contract conditions are defined by:
  - Transaction: code evaluated defining the rules to accept transaction towards the contract
  - Inherit: code evaluated defining the term of acceptance to chain a new transaction
  - Origin family: security level to restrict the origin signature and Proof of Work to the origin family set
  """
  @type t :: %__MODULE__{
          transaction: Macro.t(),
          inherit: Macro.t(),
          origin_family: nil | SharedSecrets.origin_family(),
          oracle: Macro.t()
        }
end
