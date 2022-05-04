defmodule Archethic.P2P.Message.ReplicateTransactionChain do
  @moduledoc """
  Represents a message to initiate the replication of the transaction chain related to the given transaction
  """
  @enforce_keys [:transaction]
  defstruct [:transaction, ack_storage?: false]

  alias Archethic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          ack_storage?: boolean()
        }
end
