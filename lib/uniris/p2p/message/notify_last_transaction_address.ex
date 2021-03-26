defmodule Uniris.P2P.Message.NotifyLastTransactionAddress do
  @moduledoc """
  Represents a message with to notify a pool of the last address of a previous address
  """
  @enforce_keys [:address, :previous_address, :timestamp]
  defstruct [:address, :previous_address, :timestamp]

  alias Uniris.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          previous_address: Crypto.versioned_hash(),
          timestamp: DateTime.t()
        }
end
