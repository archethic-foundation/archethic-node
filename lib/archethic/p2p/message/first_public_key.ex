defmodule Archethic.P2P.Message.FirstPublicKey do
  @moduledoc """
  Represents a message with the first public key from a transaction chain
  """

  alias Archethic.Crypto
  alias Archethic.Utils

  @enforce_keys [:public_key]
  defstruct [:public_key]

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{public_key: public_key}) do
    <<public_key::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)
    {%__MODULE__{public_key: public_key}, rest}
  end
end
