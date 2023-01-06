defmodule Archethic.P2P.Message.GetStorageNonce do
  @moduledoc """
  Represents a message to request the storage nonce

  This message is used during the node bootstrapping
  """

  alias Archethic.P2P.Message.EncryptedStorageNonce
  alias Archethic.Crypto

  @enforce_keys [:public_key]
  defstruct [:public_key]

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{public_key: public_key}) do
    <<1::8, public_key::binary>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: EncryptedStorageNonce.t()
  def process(%__MODULE__{public_key: public_key}, _) do
    %EncryptedStorageNonce{
      digest: Crypto.encrypt_storage_nonce(public_key)
    }
  end
end
