defmodule ArchEthic.P2P.Message.LastTransactionAddress do
  @moduledoc """
  Represents a message with the last address key from a transaction chain
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias ArchEthic.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }
end
