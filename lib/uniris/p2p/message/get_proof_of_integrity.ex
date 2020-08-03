defmodule Uniris.P2P.Message.GetProofOfIntegrity do
  @moduledoc """
  Represents a message to request the proof of integrity for a transaction

  This is used during the mining process when the context is retrieved to confirm the data downloaded.
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Uniris.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }
end
