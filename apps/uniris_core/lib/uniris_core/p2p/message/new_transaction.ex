defmodule UnirisCore.P2P.Message.NewTransaction do
  defstruct [:transaction]

  alias UnirisCore.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }
end
