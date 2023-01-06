defmodule Archethic.P2P.Message.GetBeaconSummaries do
  @moduledoc """
  Represents a message which get all the beacon summaries for the given addresses
  """
  defstruct [:addresses]

  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.P2P.Message.BeaconSummaryList

  @type t() :: %__MODULE__{
          addresses: list(binary())
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: BeaconSummaryList.t()
  def process(%__MODULE__{addresses: addresses}, _) do
    %BeaconSummaryList{
      summaries: BeaconChain.get_beacon_summaries(addresses)
    }
  end
end
