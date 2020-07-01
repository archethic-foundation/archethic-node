defmodule UnirisCore.P2P.Message.ReplicateTransaction do
  @enforce_keys [:transaction]
  defstruct [:transaction]

  alias UnirisCore.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }
end
