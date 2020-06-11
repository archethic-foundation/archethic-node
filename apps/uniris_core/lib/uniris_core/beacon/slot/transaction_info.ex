defmodule UnirisCore.BeaconSlot.TransactionInfo do
  defstruct [:timestamp, :address, :type, movements_addresses: []]

  @type t :: %__MODULE__{
          timestamp: DateTime.t(),
          address: binary(),
          movements_addresses: list(binary()),
          type: UnirisCore.Transaction.transaction_type()
        }
end
