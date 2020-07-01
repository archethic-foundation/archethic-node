defmodule UnirisCore.P2P.Message.GetStorageNonce do
  alias UnirisCore.Crypto

  @enforce_keys [:public_key]
  defstruct [:public_key]

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }
end
