defmodule Uniris.P2P.Message.ProofOfIntegrity do
  @moduledoc """
  Represents a message with the proof of integrity of a transaction chain
  """
  @enforce_keys [:digest]
  defstruct [:digest]

  alias Uniris.Crypto

  @type t :: %__MODULE__{
          digest: Crypto.versioned_hash()
        }
end
