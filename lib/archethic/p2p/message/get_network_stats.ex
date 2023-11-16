defmodule Archethic.P2P.Message.GetNetworkStats do
  @moduledoc """
  Represents a message to get the network stats from the beacon summary cache
  """

  @enforce_keys :subsets
  defstruct subsets: []

  alias Archethic.BeaconChain
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
  def process(%__MODULE__{subsets: subsets}, _node_public_key) do
    stats =
      subsets
      |> Task.async_stream(
        fn subset ->
          stats = BeaconChain.get_network_stats(subset)

          {subset, stats}
        end,
        on_timeout: :kill_task,
        max_concurrency: 256
      )
      |> Stream.filter(fn
        {:exit, :timeout} -> false
        _ -> true
      end)
      |> Stream.map(fn {:ok, res} -> res end)
      |> Enum.reduce(%{}, fn
        {subset, stats}, acc when map_size(stats) > 0 ->
          Map.put(acc, subset, stats)

        _, acc ->
          acc
      end)

    %NetworkStats{stats: stats}
  end
end
