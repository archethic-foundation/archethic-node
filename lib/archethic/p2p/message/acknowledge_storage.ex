defmodule Archethic.P2P.Message.AcknowledgeStorage do
  @moduledoc """
  Represents a message to notify the acknowledgment of the storage of a transaction

  This message is used during the transaction replication
  """
  @enforce_keys [:address, :signature, :node_public_key]
  defstruct [:address, :signature, :node_public_key]

  alias Archethic.Crypto

  @type t :: %__MODULE__{
          address: binary(),
          signature: binary(),
          node_public_key: Crypto.key()
        }
end
