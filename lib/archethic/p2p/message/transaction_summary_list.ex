defmodule Archethic.P2P.Message.TransactionSummaryList do
  @moduledoc """
  Represents a message with a list of transaction summary
  """
  defstruct transaction_summaries: []

  alias Archethic.TransactionChain.TransactionSummary

  @type t() :: %__MODULE__{
          transaction_summaries: list(TransactionSummary.t())
        }
end
