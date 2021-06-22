defmodule ArchEthic.P2P.Message.StartMining do
  @moduledoc """
  Represents message to start the transaction mining.

  This message is initiated by the welcome node after the validation nodes election
  """
  @enforce_keys [:transaction, :welcome_node_public_key, :validation_node_public_keys]
  defstruct [:transaction, :welcome_node_public_key, :validation_node_public_keys]

  alias ArchEthic.Crypto
  alias ArchEthic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          welcome_node_public_key: Crypto.key(),
          validation_node_public_keys: list(Crypto.key())
        }
end
