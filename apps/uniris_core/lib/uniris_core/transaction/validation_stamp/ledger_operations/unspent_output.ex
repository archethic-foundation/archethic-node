defmodule UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput do
  @enforce_keys [:amount, :from]
  defstruct [:amount, :from]

  @type t :: %__MODULE__{
          amount: float(),
          from: binary()
        }
end
