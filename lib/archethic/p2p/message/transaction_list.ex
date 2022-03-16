defmodule ArchEthic.P2P.Message.TransactionList do
  @moduledoc """
  Represents a message with a list of transactions
  """
  defstruct [:page, transactions: []]

  alias ArchEthic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transactions: list(Transaction.t()),
          page: nil | binary()
        }
end
