defmodule Archethic.P2P.Message.TransactionChainLength do
  @moduledoc """
  Represents a message with the number of transactions from a chain
  """
  defstruct [:length]

  @type t :: %__MODULE__{
          length: non_neg_integer()
        }
end
