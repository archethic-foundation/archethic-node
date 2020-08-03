defmodule Uniris.P2P.Message.TransactionHistory do
  @moduledoc """
  Represents a message with the result from the transaction context retrieval to send to the coordinator
  """
  defstruct transaction_chain: [], unspent_outputs: []

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @type t :: %__MODULE__{
          transaction_chain: list(Transaction.t()),
          unspent_outputs: list(UnspentOutput.t())
        }
end
