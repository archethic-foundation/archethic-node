defmodule ArchEthic.P2P.Message.EncryptedStorageNonce do
  @moduledoc """
  Represents a message with the requested storage nonce encrypted with the given public key

  This message is used during the node bootstrapping
  """
  @enforce_keys [:digest]
  defstruct [:digest]

  @type t :: %__MODULE__{
          digest: binary()
        }

  use ArchEthic.P2P.Message, message_id: 247

  def encode(%__MODULE__{digest: digest}) do
    <<byte_size(digest)::8, digest::binary>>
  end

  def decode(<<digest_size::8, digest::binary-size(digest_size), rest::bitstring>>) do
    {%__MODULE__{digest: digest}, rest}
  end

  def process(%__MODULE__{}) do
  end
end
