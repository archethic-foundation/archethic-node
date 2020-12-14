defmodule Uniris.Contracts.Contract.Conditions do
  @moduledoc """
  Represents the smart contract conditions
  """

  defstruct [:response, :inherit, :origin_family, :post_paid_fee]

  alias Uniris.Crypto
  alias Uniris.SharedSecrets

  @typedoc """
  Smart contract conditions are defined by:
  - Response: code evaluated defining the rules to accept transaction towards the contract
  - Inherit: code evaluated defining the term of acceptance to chain a new transaction
  - Origin family: security level to restrict the origin signature and Proof of Work to the origin family set
  - Post paid fee: Determines the address in charge of the transaction fees for the transaction towards the contract
  """
  @type t :: %__MODULE__{
          response: Macro.t(),
          inherit: Macro.t(),
          origin_family: nil | SharedSecrets.origin_family(),
          post_paid_fee: Crypto.versioned_hash()
        }
end
