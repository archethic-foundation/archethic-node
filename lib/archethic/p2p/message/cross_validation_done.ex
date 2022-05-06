defmodule Archethic.P2P.Message.CrossValidationDone do
  @moduledoc """
  Represents a message to notify the end of the cross validation for a given transaction address

  This message is used during the mining process by the cross validation nodes.
  """
  @enforce_keys [:address, :cross_validation_stamp]
  defstruct [:address, :cross_validation_stamp]

  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          cross_validation_stamp: CrossValidationStamp.t()
        }
end
