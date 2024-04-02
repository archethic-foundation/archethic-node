defmodule Archethic.P2P.Message.GetBeaconSummaries do
  @moduledoc """
  Represents a message which get all the beacon summaries for the given addresses
  """
  defstruct [:addresses]

  alias Archethic.BeaconChain
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.BeaconSummaryList
  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @type t() :: %__MODULE__{
          addresses: list(binary())
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: BeaconSummaryList.t()
  def process(%__MODULE__{addresses: addresses}, _) do
    %BeaconSummaryList{
      summaries: BeaconChain.get_beacon_summaries(addresses)
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{addresses: addresses}) do
    encoded_addresses_length = length(addresses) |> VarInt.from_value()
    <<encoded_addresses_length::binary, :erlang.list_to_binary(addresses)::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_addresses, rest} = rest |> VarInt.get_value()
    {addresses, rest} = Utils.deserialize_addresses(rest, nb_addresses, [])

    {
      %__MODULE__{addresses: addresses},
      rest
    }
  end
end
