defmodule UnirisCore.BeaconSlot.TransactionInfo do
  defstruct [:timestamp, :address, :type]

  @type t :: %__MODULE__{
          timestamp: non_neg_integer(),
          address: binary(),
          type: UnirisCore.Transaction.transaction_type()
        }
end
