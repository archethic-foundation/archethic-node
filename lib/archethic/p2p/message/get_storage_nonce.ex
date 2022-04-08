defmodule ArchEthic.P2P.Message.GetStorageNonce do
  @moduledoc """
  Represents a message to request the storage nonce

  This message is used during the node bootstrapping
  """

  alias ArchEthic.Crypto
  alias ArchEthic.P2P.Message.EncryptedStorageNonce
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 1

  @enforce_keys [:public_key]
  defstruct [:public_key]

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }

  def encode(%__MODULE__{public_key: public_key}) do
    public_key
  end

  def decode(message) when is_bitstring(message) do
    {public_key, rest} = Utils.deserialize_public_key(message)

    {
      %__MODULE__{
        public_key: public_key
      },
      rest
    }
  end

  def process(%__MODULE__{public_key: public_key}) do
    %EncryptedStorageNonce{
      digest: Crypto.encrypt_storage_nonce(public_key)
    }
  end
end
