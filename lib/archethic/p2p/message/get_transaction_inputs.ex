defmodule Archethic.P2P.Message.GetTransactionInputs do
  @moduledoc """
  Represents a message with to request the inputs (spent or unspents) from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }
end
