defmodule UnirisCore.P2P.Message.EncryptedStorageNonce do
  @enforce_keys [:digest]
  defstruct [:digest]

  @type t :: %__MODULE__{
          digest: binary()
        }
end
