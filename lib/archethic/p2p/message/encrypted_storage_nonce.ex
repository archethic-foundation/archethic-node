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

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{digest: digest}) do
    <<byte_size(digest)::8, digest::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<digest_size::8, digest::binary-size(digest_size), rest::bitstring>>) do
    {%__MODULE__{
       digest: digest
     }, rest}
  end
end
