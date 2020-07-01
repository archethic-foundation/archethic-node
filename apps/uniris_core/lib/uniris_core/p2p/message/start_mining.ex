defmodule UnirisCore.P2P.Message.StartMining do
  @enforce_keys [:transaction, :welcome_node_public_key, :validation_node_public_keys]
  defstruct [:transaction, :welcome_node_public_key, :validation_node_public_keys]

  alias UnirisCore.Transaction
  alias UnirisCore.Crypto

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          welcome_node_public_key: Crypto.key(),
          validation_node_public_keys: list(Crypto.key())
        }
end
