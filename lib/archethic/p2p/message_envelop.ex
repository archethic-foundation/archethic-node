defmodule ArchEthic.P2P.MessageEnvelop do
  @moduledoc """
  Represents the message envelop foreach P2P messages
  """

  defstruct [
    :message_id,
    :message,
    :sender_public_key
  ]

  alias ArchEthic.Crypto
  alias ArchEthic.P2P.Message
  alias ArchEthic.Utils

  @type t :: %__MODULE__{
          message: Message.t(),
          message_id: non_neg_integer(),
          sender_public_key: Crypto.key()
        }

  @doc """
  Encode a message envelop in a binary format
  """
  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{
        message_id: message_id,
        sender_public_key: sender_public_key,
        message: message
      }) do
    encoded_message =
      message
      |> Message.encode()
      |> Utils.wrap_binary()

    <<message_id::32, 0::8, sender_public_key::binary, encoded_message::binary>>
  end

  @doc """
  Same as encode/1 except the data will be encrypted with the given recipient public key
  """
  @spec encode(t(), Crypto.key()) :: bitstring()
  def encode(
        %__MODULE__{
          message_id: message_id,
          sender_public_key: sender_public_key,
          message: message
        },
        recipient_public_key
      )
      when is_binary(recipient_public_key) do
    encrypted_message =
      message
      |> Message.encode()
      |> Utils.wrap_binary()
      |> Crypto.ec_encrypt(recipient_public_key)

    <<message_id::32, 1::8, sender_public_key::binary, encrypted_message::binary>>
  end

  @doc """
  Decode a encoded message envelop.

  It will detect if the message is encrypted and try to decrypt with the current node private key.
  """
  @spec decode(bitstring()) :: t()
  def decode(<<message_id::32, 0::8, curve_id::8, origin_id::8, rest::binary>>) do
    key_size = Crypto.key_size(curve_id)
    <<public_key::binary-size(key_size), rest::binary>> = rest

    {data, _} = Message.decode(rest)
    sender_public_key = <<curve_id::8, origin_id::8, public_key::binary>>
    %__MODULE__{message_id: message_id, message: data, sender_public_key: sender_public_key}
  end

  def decode(<<message_id::32, 1::8, curve_id::8, origin_id::8, rest::binary>>) do
    key_size = Crypto.key_size(curve_id)
    <<public_key::binary-size(key_size), encrypted_message::binary>> = rest
    message = Crypto.ec_decrypt_with_first_node_key!(encrypted_message)

    {data, _} = Message.decode(message)

    sender_public_key = <<curve_id::8, origin_id::8, public_key::binary>>
    %__MODULE__{message_id: message_id, message: data, sender_public_key: sender_public_key}
  end
end
