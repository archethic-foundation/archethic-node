defmodule Uniris.P2P.Message.GetStorageNonce do
  @moduledoc """
  Represents a message to request the storage nonce

  This message is used during the node bootstrapping
  """
  alias Uniris.Crypto

  @enforce_keys [:public_key]
  defstruct [:public_key]

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }
end
