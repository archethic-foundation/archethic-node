defmodule UnirisCore.P2P.Message.TransactionList do
  defstruct transactions: []

  alias UnirisCore.Transaction

  @type t :: %__MODULE__{
          transactions: list(Transaction.t())
        }
end
