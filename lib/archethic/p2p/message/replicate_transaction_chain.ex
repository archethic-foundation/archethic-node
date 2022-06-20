defmodule Archethic.P2P.Message.ReplicateTransactionChain do
  @moduledoc """
  Represents a message to initiate the replication of the transaction chain related to the given transaction
  """
  @enforce_keys [:transaction]
  defstruct [:transaction]

  alias Archethic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }
end
