defmodule Archethic.P2P.Message.GetFirstPublicKey do
  @moduledoc """
  Represents a message to request the first public key from a transaction chain
  """

  @enforce_keys [:public_key]
  defstruct [:public_key]

  alias Archethic.Utils
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.FirstPublicKey

  @type t() :: %__MODULE__{
          public_key: binary()
        }

  # Returns the first public_key for a given public_key and if the public_key is used for the first time, return the same public_key.
  @spec process(__MODULE__.t(), Message.metadata()) :: FirstPublicKey.t()
  def process(%__MODULE__{public_key: public_key}, _) do
    %FirstPublicKey{
      public_key: TransactionChain.get_first_public_key(public_key)
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{public_key: public_key}) do
    <<public_key::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)

    {%__MODULE__{
       public_key: public_key
     }, rest}
  end
end
