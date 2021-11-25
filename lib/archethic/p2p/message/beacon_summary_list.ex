defmodule ArchEthic.P2P.Message.BeaconSummaryList do
  @moduledoc """
  Represents a message with a list of beacon summaries
  """

  alias ArchEthic.BeaconChain.Summary

  defstruct summaries: []

  @type t :: %__MODULE__{
          summaries: list(Summary.t())
        }
end
