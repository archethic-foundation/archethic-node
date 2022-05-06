defmodule Archethic.P2P.Message.GetTransaction do
  @moduledoc """
  Represents a message to request a transaction
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }
end
