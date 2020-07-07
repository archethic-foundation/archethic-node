defmodule UnirisCore.P2P.Message.TransactionChainLength do
  defstruct [:length]

  @type t :: %__MODULE__{
          length: non_neg_integer()
        }
end
