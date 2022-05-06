defmodule Archethic.P2P.Message.GetLastTransaction do
  @moduledoc """
  Represents a message to request the last transaction of a chain
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }
end
