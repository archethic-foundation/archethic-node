defmodule UnirisCore.Transaction.ValidationStamp.LedgerOperations.Movement do
  @enforce_keys [:to, :amount]
  defstruct [:to, :amount]

  @type t() :: %__MODULE__{
          to: binary(),
          amount: float()
        }
end
