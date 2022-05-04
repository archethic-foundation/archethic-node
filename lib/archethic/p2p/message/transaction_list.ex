defmodule Archethic.P2P.Message.TransactionList do
  @moduledoc """
  Represents a message with a list of transactions
  """
  defstruct transactions: [], more?: false, paging_state: nil

  alias Archethic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transactions: list(Transaction.t()),
          paging_state: nil | binary(),
          more?: boolean()
        }
end
