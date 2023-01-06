defmodule Archethic.P2P.Message.FirstPublicKey do
  @moduledoc """
  Represents a message with the first public key from a transaction chain
  """

  alias Archethic.Crypto

  @enforce_keys [:public_key]
  defstruct [:public_key]

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{public_key: public_key}) do
    <<242::8, public_key::binary>>
  end
end
