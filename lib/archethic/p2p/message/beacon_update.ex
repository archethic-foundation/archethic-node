defmodule ArchEthic.P2P.Message.BeaconUpdate do
  @moduledoc """
  Represents a message to get a beacon updates
  """

  @enforce_keys [:tx_summary]
  defstruct [:tx_summary]

  alias ArchEthic.BeaconChain.Slot.TransactionSummary

  @type t :: %__MODULE__{
          tx_summary: TransactionSummary.t()
        }
end
