defmodule Archethic.P2P.Message.AcknowledgeStorage do
  @moduledoc """
  Represents a message to notify the acknowledgment of the storage of a transaction

  This message is used during the transaction replication
  """

  @enforce_keys [:address, :signature, :node_public_key]
  defstruct [:address, :signature, :node_public_key]

  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.P2P.Message.Ok

  @type t :: %__MODULE__{
          address: binary(),
          signature: binary()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{
          address: address,
          signature: signature,
          node_public_key: node_public_key
        },
        _
      ) do
    Mining.confirm_replication(address, signature, node_public_key)
    %Ok{}
  end
end
