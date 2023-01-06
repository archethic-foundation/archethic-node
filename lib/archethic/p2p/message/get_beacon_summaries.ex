defmodule Archethic.P2P.Message.GetBeaconSummaries do
  @moduledoc """
  Represents a message which get all the beacon summaries for the given addresses
  """
  defstruct [:addresses]

  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.P2P.Message.BeaconSummaryList
  alias Archethic.Utils.VarInt

  @type t() :: %__MODULE__{
          addresses: list(binary())
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{addresses: addresses}) do
    encoded_addresses_length = length(addresses) |> VarInt.from_value()
    <<28::8, encoded_addresses_length::binary, :erlang.list_to_binary(addresses)::binary>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: BeaconSummaryList.t()
  def process(%__MODULE__{addresses: addresses}, _) do
    %BeaconSummaryList{
      summaries: BeaconChain.get_beacon_summaries(addresses)
    }
  end
end
