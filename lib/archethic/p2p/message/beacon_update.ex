defmodule ArchEthic.P2P.Message.BeaconUpdate do
  @moduledoc """
  Represents a message to get a beacon updates
  """

  @enforce_keys [:transaction_summaries]
  defstruct [:transaction_summaries]

  alias ArchEthic.BeaconChain.Slot.TransactionSummary

  @type t :: %__MODULE__{
          transaction_summaries: list(TransactionSummary.t())
        }
end
