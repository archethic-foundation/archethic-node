defmodule UnirisCore.BeaconSlot.TransactionInfo do
  defstruct [:timestamp, :address, :type]

  @type t :: %__MODULE__{
          timestamp: DateTime.t(),
          address: binary(),
          type: UnirisCore.Transaction.transaction_type()
        }
end
