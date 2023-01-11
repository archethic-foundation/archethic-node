defmodule Archethic.P2P.Message.AcknowledgeStorage do
  @moduledoc """
  Represents a message to notify the acknowledgment of the storage of a transaction

  This message is used during the transaction replication
  """
  @enforce_keys [:address, :signature]
  defstruct [:address, :signature]

  @type t :: %__MODULE__{
          address: binary(),
          signature: binary()
        }
end
