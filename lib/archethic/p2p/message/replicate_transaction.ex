defmodule ArchEthic.P2P.Message.ReplicateTransaction do
  @moduledoc """
  Represents a message to initiate the replication of the transaction
  """
  @enforce_keys [:transaction]
  defstruct [:transaction, roles: [], ack_storage?: false]

  alias ArchEthic.Replication
  alias ArchEthic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          roles: list(Replication.role()),
          ack_storage?: boolean()
        }
end
