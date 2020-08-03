defmodule Uniris.P2P.Message.TransactionList do
  @moduledoc """
  Represents a message with a list of transactions
  """
  defstruct transactions: []

  alias Uniris.Transaction

  @type t :: %__MODULE__{
          transactions: list(Transaction.t())
        }
end
