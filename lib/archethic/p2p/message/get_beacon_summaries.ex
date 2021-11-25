defmodule ArchEthic.P2P.Message.GetBeaconSummaries do
  @moduledoc """
  Represents a message which get all the beacon summaries for the given addresses
  """
  defstruct [:addresses]

  @type t() :: %__MODULE__{
          addresses: list(binary())
        }
end
