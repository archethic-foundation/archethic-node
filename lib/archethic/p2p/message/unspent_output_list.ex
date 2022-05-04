defmodule Archethic.P2P.Message.UnspentOutputList do
  @moduledoc """
  Represents a message with a list of unspent outputs
  """
  defstruct unspent_outputs: []

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @type t :: %__MODULE__{
          unspent_outputs: list(UnspentOutput.t())
        }
end
