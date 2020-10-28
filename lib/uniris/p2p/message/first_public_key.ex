defmodule Uniris.P2P.Message.FirstPublicKey do
  @moduledoc """
  Represents a message with the first public key from a transaction chain
  """

  alias Uniris.Crypto

  @enforce_keys [:public_key]
  defstruct [:public_key]

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }
end
