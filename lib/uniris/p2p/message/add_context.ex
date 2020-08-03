defmodule Uniris.P2P.Message.AddContext do
  @moduledoc """
  Represents a message to request the add of a context retrieval to the coordinator

  This message is used in the transaction mining by the cross validation nodes
  """
  @enforce_keys [:address, :validation_node_public_key, :context]
  defstruct [:address, :validation_node_public_key, :context]

  alias Uniris.Crypto
  alias Uniris.Mining.Context

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          validation_node_public_key: Crypto.key(),
          context: Context.t()
        }
end
