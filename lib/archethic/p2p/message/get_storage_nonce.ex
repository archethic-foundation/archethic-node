defmodule Archethic.P2P.Message.GetStorageNonce do
  @moduledoc """
  Represents a message to request the storage nonce

  This message is used during the node bootstrapping
  """

  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.EncryptedStorageNonce
  alias Archethic.Crypto
  alias Archethic.Utils

  @enforce_keys [:public_key]
  defstruct [:public_key]

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {public_key, rest} = Utils.deserialize_public_key(bin)

    {
      %__MODULE__{
        public_key: public_key
      },
      rest
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{public_key: public_key}) do
    <<public_key::binary>>
  end

  @spec process(__MODULE__.t(), Message.metadata()) :: EncryptedStorageNonce.t()
  def process(%__MODULE__{public_key: public_key}, _) do
    %EncryptedStorageNonce{
      digest: Crypto.encrypt_storage_nonce(public_key)
    }
  end
end
