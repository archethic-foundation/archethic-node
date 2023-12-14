defmodule Archethic.P2P.Message.GetNetworkStats do
  @moduledoc """
  Represents a message to get the network stats from the beacon summary cache
  """

  @enforce_keys :subsets
  defstruct subsets: []

  alias Archethic.BeaconChain.Subset.StatsCollector
  alias Archethic.Crypto
  alias Archethic.P2P.Message.NetworkStats

  @type t :: %__MODULE__{
          subsets: list(binary())
        }

  @doc """
  Serialize the get network stats message into binary

  ## Examples

      iex> %GetNetworkStats{subsets: [<<0>>, <<255>>]} |> GetNetworkStats.serialize()
      <<
      # Length of subsets
      0, 2,
      # Subset
      0, 255
      >>
  """
  def serialize(%__MODULE__{subsets: subsets}) do
    <<length(subsets)::16, :erlang.list_to_binary(subsets)::binary>>
  end

  @doc """
  Deserialize the binary into the get network stats message

  ## Examples

      iex> <<0, 2, 0, 255>> |> GetNetworkStats.deserialize()
      {
        %GetNetworkStats{subsets: [<<0>>, <<255>>]},
        ""
      }
  """
  def deserialize(<<length::16, subsets_binary::binary-size(length), rest::bitstring>>) do
    subsets =
      subsets_binary
      |> :erlang.binary_to_list()
      |> Enum.map(&<<&1>>)

    {
      %__MODULE__{subsets: subsets},
      rest
    }
  end

  @doc """
  Process the message to get the network stats from the summary cache
  """
  @spec process(t(), Crypto.key()) :: NetworkStats.t()
  def process(%__MODULE__{}, _node_public_key) do
    # we do not use the `subsets` argument anymore.
    # the node will always reply with the stats from the subsets it is elected to store
    %NetworkStats{stats: StatsCollector.get()}
  end
end
