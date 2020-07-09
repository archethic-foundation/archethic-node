defmodule UnirisCore.P2P.Message.ReplicateTransaction do
  @moduledoc """
  Represents a message to initiate the replication of the transaction
  """
  @enforce_keys [:transaction]
  defstruct [:transaction]

  alias UnirisCore.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }
end
