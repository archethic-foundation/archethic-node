defmodule UnirisCore.P2P.Message.AddContext do
  @enforce_keys [:address, :validation_node_public_key, :context]
  defstruct [:address, :validation_node_public_key, :context]

  alias UnirisCore.Crypto
  alias UnirisCore.Mining.Context

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          validation_node_public_key: Crypto.key(),
          context: Context.t()
        }
end
