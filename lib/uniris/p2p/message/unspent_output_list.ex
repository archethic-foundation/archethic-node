defmodule Uniris.P2P.Message.UnspentOutputList do
  @moduledoc """
  Represents a message with a list of unspent outputs
  """
  defstruct unspent_outputs: []

  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @type t :: %__MODULE__{
          unspent_outputs: list(UnspentOutput.t())
        }
end
