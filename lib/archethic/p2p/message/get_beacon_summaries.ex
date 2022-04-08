defmodule ArchEthic.P2P.Message.GetBeaconSummaries do
  @moduledoc """
  Represents a message which get all the beacon summaries for the given addresses
  """
  defstruct [:addresses]

  @type t() :: %__MODULE__{
          addresses: list(binary())
        }

  alias ArchEthic.BeaconChain
  alias ArchEthic.P2P.Message.BeaconSummaryList
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 28

  def encode(%__MODULE__{addresses: addresses}),
    do: <<length(addresses)::32, :erlang.list_to_binary(addresses)::binary>>

  def decode(<<nb_addresses::32, rest::bitstring>>) do
    {addresses, rest} = Utils.deserialize_addresses(rest, nb_addresses, [])

    {
      %__MODULE__{addresses: addresses},
      rest
    }
  end

  def process(%__MODULE__{addresses: addresses}) do
    %BeaconSummaryList{
      summaries: BeaconChain.get_beacon_summaries(addresses)
    }
  end
end
