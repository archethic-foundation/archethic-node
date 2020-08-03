defmodule Uniris.P2P.Message.GetTransactionHistory do
  @moduledoc """
  Represents a message to request the transaction history

  This message is sent during the mining when the validation nodes have to rebuild the transaction context.
  (transaction chain + unspent outputs)
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Uniris.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }
end
