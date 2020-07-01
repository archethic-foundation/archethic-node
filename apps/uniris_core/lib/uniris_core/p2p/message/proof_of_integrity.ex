defmodule UnirisCore.P2P.Message.ProofOfIntegrity do
  @enforce_keys [:digest]
  defstruct [:digest]

  alias UnirisCore.Crypto

  @type t :: %__MODULE__{
          digest: Crypto.versioned_hash()
        }
end
