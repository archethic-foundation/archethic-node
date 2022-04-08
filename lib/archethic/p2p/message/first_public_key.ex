defmodule ArchEthic.P2P.Message.FirstPublicKey do
  @moduledoc """
  Represents a message with the first public key from a transaction chain
  """

  alias ArchEthic.Crypto
  alias ArchEthic.Utils

  @enforce_keys [:public_key]
  defstruct [:public_key]

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }
  use ArchEthic.P2P.Message, message_id: 20

  def encode(%__MODULE__{public_key: public_key}) do
    <<public_key::binary>>
  end

  def decode(message) do
    {public_key, rest} = Utils.deserialize_public_key(message)

    {
      %__MODULE__{public_key: public_key},
      rest
    }
  end

  def process(%__MODULE__{}) do
  end
end
