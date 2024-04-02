defmodule Archethic.P2P.Message.AcknowledgeStorage do
  @moduledoc """
  Represents a message to notify the acknowledgment of the storage of a transaction

  This message is used during the transaction replication
  """

  @enforce_keys [:address, :signature]
  defstruct [:address, :signature]

  alias Archethic.Mining
  alias Archethic.Utils
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok

  @type t :: %__MODULE__{
          address: binary(),
          signature: binary()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t()
  def process(
        %__MODULE__{
          address: address,
          signature: signature
        },
        %{sender_public_key: node_public_key}
      ) do
    Mining.confirm_replication(address, signature, node_public_key)
    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        address: address,
        signature: signature
      }) do
    <<address::binary, byte_size(signature)::8, signature::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, <<signature_size::8, signature::binary-size(signature_size), rest::bitstring>>} =
      Utils.deserialize_address(bin)

    {%__MODULE__{
       address: address,
       signature: signature
     }, rest}
  end
end
