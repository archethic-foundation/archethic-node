defmodule Uniris.P2P.Message.GetLastTransactionAddress do
  @moduledoc """
  Represents a message to request the last transaction address of a chain
  """
  @enforce_keys [:address, :timestamp]
  defstruct [:address, :timestamp]

  alias Uniris.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          timestamp: DateTime.t()
        }
end
