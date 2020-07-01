defmodule UnirisCore.P2P.Message.UnspentOutputList do
  defstruct unspent_outputs: []

  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @type t :: %__MODULE__{
          unspent_outputs: list(UnspentOutput.t())
        }
end
