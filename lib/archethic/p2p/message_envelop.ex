defmodule Archethic.P2P.MessageEnvelop do
  @moduledoc """
  Represents the message envelop foreach P2P messages
  """

  @enforce_keys [:message_id, :message, :sender_public_key, :signature]
  defstruct [
    :message_id,
    :message,
    :sender_public_key,
    :signature,
    :decrypted_raw_message,
    trace: ""
  ]

  alias Archethic.Crypto
  alias Archethic.P2P.Message
  alias Archethic.Utils

  @type t :: %__MODULE__{
          message: Message.t(),
          message_id: non_neg_integer(),
          sender_public_key: Crypto.key(),
          signature: binary(),
          decrypted_raw_message: binary() | nil,
          trace: binary()
        }

  @doc """
  Encode a message envelop in a binary format
  """
  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{
        message_id: message_id,
        sender_public_key: sender_public_key,
        message: message,
        signature: signature,
        trace: trace
      }) do
    encoded_message =
      message
      |> Message.encode()
      |> Utils.wrap_binary()

    <<message_id::32, 0::8, sender_public_key::binary, byte_size(trace)::8, trace::binary,
      byte_size(signature)::8, signature::binary, encoded_message::binary>>
  end

  @doc """
  Same as encode/1 except the data will be encrypted with the given recipient public key
  """
  @spec encode(t(), Crypto.key()) :: bitstring()
  def encode(
        %__MODULE__{
          message_id: message_id,
          sender_public_key: sender_public_key,
          message: message,
          signature: signature,
          trace: trace
        },
        recipient_public_key
      )
      when is_binary(recipient_public_key) do
    encrypted_message =
      message
      |> Message.encode()
      |> Utils.wrap_binary()
      |> Crypto.ec_encrypt(recipient_public_key)

    <<message_id::32, 1::8, sender_public_key::binary, byte_size(trace)::8, trace::binary,
      byte_size(signature)::8, signature::binary, encrypted_message::binary>>
  end

  @doc """
  Decode a encoded message envelop.

  It will detect if the message is encrypted and try to decrypt with the current node private key.
  """
  @spec decode(bitstring()) :: t()
  def decode(<<message_id::32, 0::8, curve_id::8, origin_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)

    <<public_key::binary-size(key_size), trace_size::8, trace::binary-size(trace_size),
      signature_size::8, signature::binary-size(signature_size), message::bitstring>> = rest

    {data, _} = Message.decode(message)

    sender_public_key = <<curve_id::8, origin_id::8, public_key::binary>>

    %__MODULE__{
      message_id: message_id,
      message: data,
      sender_public_key: sender_public_key,
      signature: signature,
      decrypted_raw_message: message,
      trace: trace
    }
  end

  def decode(<<message_id::32, 1::8, curve_id::8, origin_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)

    <<public_key::binary-size(key_size), trace_size::8, trace::binary-size(trace_size),
      signature_size::8, signature::binary-size(signature_size),
      encrypted_message::bitstring>> = rest

    message = Crypto.ec_decrypt_with_first_node_key!(encrypted_message)

    {data, _} = Message.decode(message)

    sender_public_key = <<curve_id::8, origin_id::8, public_key::binary>>

    %__MODULE__{
      message_id: message_id,
      message: data,
      sender_public_key: sender_public_key,
      signature: signature,
      decrypted_raw_message: message,
      trace: trace
    }
  end

  @doc """
  Decode the raw message without any decryption or deserialization.

  This can be useful, if you want to decode an encrypted content but not decrypt it with the node's private key
  """
  @spec decode_raw_message(bitstring()) :: {non_neg_integer(), bitstring()}
  def decode_raw_message(<<message_id::32, _::8, curve_id::8, _origin_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)

    <<_public_key::binary-size(key_size), trace_size::8, _trace::binary-size(trace_size),
      signature_size::8, _signature::binary-size(signature_size),
      encrypted_message::bitstring>> = rest

    {message_id, encrypted_message}
  end
end
