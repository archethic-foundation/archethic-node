defmodule Archethic.P2P.Message.BeaconSummaryList do
  @moduledoc """
  Represents a message with a list of beacon summaries
  """

  alias Archethic.BeaconChain.Summary

  defstruct summaries: []

  @type t :: %__MODULE__{
          summaries: list(Summary.t())
        }
end
