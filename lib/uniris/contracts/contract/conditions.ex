defmodule Uniris.Contracts.Contract.Conditions do
  @moduledoc """
  Represents the smart contract conditions
  """

  @default_inherit_constraints Code.string_to_quoted!("""
                                 next_transaction.code == previous_transaction.code and
                                   next_transaction.authorized_keys == previous_transaction.authorized_keys and
                                   next_transaction.secret == previous_transaction.secret and
                                   next_transaction.content == previous_transaction.content and
                                   next_transaction.uco_transferred == 0.0 and next_transaction.nft_transferred == 0.0
                               """)

  defstruct [
    :transaction,
    :origin_family,
    inherit: @default_inherit_constraints
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
          origin_family: nil | SharedSecrets.origin_family()
        }
end
