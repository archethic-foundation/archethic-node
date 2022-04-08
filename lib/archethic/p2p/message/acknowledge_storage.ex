defmodule ArchEthic.P2P.Message.AcknowledgeStorage do
  @moduledoc """
  Represents a message to notify the acknowledgment of the storage of a transaction

  This message is used during the transaction replication
  """
  @enforce_keys [:signature]
  defstruct [:signature]

  use ArchEthic.P2P.Message, message_id: 13

  @type t :: %__MODULE__{
          signature: binary()
        }

  def encode(%__MODULE__{signature: signature}),
    do: <<byte_size(signature)::8, signature::binary>>

  def decode(<<signature_size::8, signature::binary-size(signature_size), rest::bitstring>>),
    do: {%__MODULE__{signature: signature}, rest}

  def process(%__MODULE__{}) do
  end
end
