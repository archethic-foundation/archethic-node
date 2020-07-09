defmodule UnirisCore.P2P.Message.GetBalance do
  @moduledoc """
  Represents a message to request the balance of a transaction
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias UnirisCore.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }
end
