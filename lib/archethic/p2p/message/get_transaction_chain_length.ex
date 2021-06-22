defmodule ArchEthic.P2P.Message.GetTransactionChainLength do
  @moduledoc """
  Represents a message to request the size of the transaction chain (number of transactions)
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias ArchEthic.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }
end
