defmodule ArchEthic.P2P.Message.CrossValidate do
  @moduledoc """
  Represents a message to request the cross validation of a validation stamp
  """
  @enforce_keys [:address, :validation_stamp, :replication_tree]
  defstruct [:address, :validation_stamp, :replication_tree]

  alias ArchEthic.Crypto
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          validation_stamp: ValidationStamp.t(),
          replication_tree: %{
            chain: list(bitstring()),
            beacon: list(bitstring()),
            IO: list(bitstring())
          }
        }
end
