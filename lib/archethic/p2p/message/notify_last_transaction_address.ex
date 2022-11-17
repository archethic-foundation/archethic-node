defmodule Archethic.P2P.Message.NotifyLastTransactionAddress do
  @moduledoc """
  Represents a message with to notify a pool of the last address of a previous address
  """
  @enforce_keys [:last_address, :genesis_address, :timestamp]
  defstruct [:last_address, :genesis_address, :timestamp]

  alias Archethic.Crypto

  @type t :: %__MODULE__{
          last_address: Crypto.versioned_hash(),
          genesis_address: Crypto.versioned_hash(),
          timestamp: DateTime.t()
        }
end
