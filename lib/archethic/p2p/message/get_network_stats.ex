defmodule Archethic.P2P.Message.GetNetworkStats do
  @moduledoc """
  Represents a message to get the network stats from the beacon summary cache
  """

  @enforce_keys [:summary_time]
  defstruct [:summary_time]

  alias Archethic.BeaconChain.NetworkCoordinates
  alias Archethic.BeaconChain.Subset.StatsCollector
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.NetworkStats

  @type t :: %__MODULE__{
          summary_time: DateTime.t()
        }

  @doc """
  Serialize the get network stats message into binary
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{summary_time: summary_time}) do
    <<DateTime.to_unix(summary_time)::32>>
  end

  @doc """
  Deserialize the binary into the get network stats message
  """
  @spec deserialize(bitstring) :: {t(), bitstring()}
  def deserialize(<<unix::32, rest::bitstring>>) do
    summary_time = DateTime.from_unix!(unix)

    {
      %__MODULE__{summary_time: summary_time},
      rest
    }
  end

  @doc """
  Process the message to get the network stats from the summary cache
  """
  @spec process(t(), Message.metadata()) :: NetworkStats.t()
  def process(%__MODULE__{summary_time: summary_time}, _node_public_key) do
    %NetworkStats{stats: StatsCollector.get(summary_time, NetworkCoordinates.timeout())}
  end
end
