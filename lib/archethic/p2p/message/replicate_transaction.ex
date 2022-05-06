defmodule Archethic.P2P.Message.ReplicateTransaction do
  @moduledoc """
  Represents a message to initiate the replication of the transaction
  """
  @enforce_keys [:transaction]
  defstruct [:transaction]

  alias Archethic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }
end
