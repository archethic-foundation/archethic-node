defmodule UnirisCore.P2P.Message.CrossValidate do
  @moduledoc """
  Represents a message to request the cross validation of a validation stamp
  """
  @enforce_keys [:address, :validation_stamp, :replication_tree]
  defstruct [:address, :validation_stamp, :replication_tree]

  alias UnirisCore.Crypto
  alias UnirisCore.Transaction.ValidationStamp

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          validation_stamp: ValidationStamp.t(),
          replication_tree: list(bitstring())
        }
end
