defmodule ArchEthic.P2P.Message.AcknowledgeStorage do
  @moduledoc """
  Represents a message to notify the acknowledgment of the storage of a transaction

  This message is used during the transaction replication
  """
  @enforce_keys [:transaction_summary, :node_public_key, :signature]
  defstruct [:transaction_summary, :node_public_key, :signature]

  alias ArchEthic.Crypto
  alias ArchEthic.TransactionChain.TransactionSummary

  @type t :: %__MODULE__{
          transaction_summary: TransactionSummary.t(),
          node_public_key: Crypto.key(),
          signature: binary()
        }
end
