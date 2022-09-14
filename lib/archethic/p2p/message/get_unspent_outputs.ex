defmodule Archethic.P2P.Message.GetUnspentOutputs do
  @moduledoc """
  Represents a message to request the list of unspent outputs from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address, offset: 0]

  alias Archethic.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          offset: non_neg_integer()
        }
end
