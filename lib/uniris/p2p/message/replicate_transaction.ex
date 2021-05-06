defmodule Uniris.P2P.Message.ReplicateTransaction do
  @moduledoc """
  Represents a message to initiate the replication of the transaction
  """
  @enforce_keys [:transaction, :roles]
  defstruct [:transaction, :roles, ack_storage?: false]

  alias Uniris.Replication
  alias Uniris.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          roles: list(Replication.role()),
          ack_storage?: boolean()
        }
end
