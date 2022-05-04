defmodule Archethic.P2P.Message.EncryptedStorageNonce do
  @moduledoc """
  Represents a message with the requested storage nonce encrypted with the given public key

  This message is used during the node bootstrapping
  """
  @enforce_keys [:digest]
  defstruct [:digest]

  @type t :: %__MODULE__{
          digest: binary()
        }
end
