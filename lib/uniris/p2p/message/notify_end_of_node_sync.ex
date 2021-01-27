defmodule Uniris.P2P.Message.NotifyEndOfNodeSync do
  @moduledoc """
  Represents a message to request to add an information in the beacon chain regarding a node readyness

  This message is used during the node bootstrapping.
  """
  @enforce_keys [:node_public_key, :timestamp]
  defstruct [:node_public_key, :timestamp]

  alias Uniris.Crypto

  @type t :: %__MODULE__{
          node_public_key: Crypto.key(),
          timestamp: DateTime.t()
        }
end
