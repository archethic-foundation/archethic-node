defmodule ArchEthic.P2P.Message.TransactionList do
  @moduledoc """
  Represents a message with a list of transactions
  """
  defstruct [:page, transactions: [], more?: false]

  alias ArchEthic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transactions: list(Transaction.t()),
          page: nil | binary(),
          more?: boolean()
        }
end
