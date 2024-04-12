defmodule Archethic.P2P.Message.NetworkStats do
  @moduledoc """
  Represents network stats from the aggregated beacon chain summary's cache
  """

  defstruct stats: %{}

  alias Archethic.BeaconChain.Slot
  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          stats: %{
            (subset :: binary) => %{
              Crypto.key() => Slot.net_stats()
            }
          }
        }

  @doc """
  Serializes the network stats into binary

  ## Examples

      iex> %NetworkStats{
      ...>   stats: %{
      ...>     <<0>> => %{
      ...>       <<0, 0, 75, 23, 134, 64, 221, 117, 107, 77, 233, 123, 201, 244, 18, 151, 8, 255,
      ...>         53, 137, 251, 197, 67, 25, 38, 95, 2, 62, 216, 131, 112, 116, 238, 180>> => [
      ...>         %{latency: 100},
      ...>         %{latency: 110},
      ...>         %{latency: 80}
      ...>       ]
      ...>     }
      ...>   }
      ...> }
      ...> |> NetworkStats.serialize()
      <<0, 1, 0, 1, 1, 0, 0, 75, 23, 134, 64, 221, 117, 107, 77, 233, 123, 201, 244, 18, 151, 8,
        255, 53, 137, 251, 197, 67, 25, 38, 95, 2, 62, 216, 131, 112, 116, 238, 180, 1, 3, 1, 100,
        1, 110, 1, 80>>
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{stats: stats}) do
    nb_subsets = map_size(stats)

    stats_binary =
      Enum.map(stats, fn {subset, stats} ->
        serialize_subset_stats(subset, stats)
      end)
      |> :erlang.list_to_binary()

    <<nb_subsets::16, stats_binary::binary>>
  end

  defp serialize_subset_stats(subset, stats) do
    stats_bin =
      stats
      |> Enum.map(fn {node_public_key, latencies} ->
        nb_latencies_bin = VarInt.from_value(length(latencies))

        latency_bin =
          latencies
          |> Enum.map(fn %{latency: latency} -> VarInt.from_value(latency) end)
          |> :erlang.list_to_binary()

        <<node_public_key::binary, nb_latencies_bin::binary, latency_bin::binary>>
      end)
      |> :erlang.list_to_binary()

    nb_stats = map_size(stats)
    nb_stats_bin = VarInt.from_value(nb_stats)
    <<subset::binary-size(1), nb_stats_bin::binary, stats_bin::binary>>
  end

  @doc """
  Deserialize the binary into a network stats message

  ## Examples

      iex> <<0, 1, 0, 1, 1, 0, 0, 75, 23, 134, 64, 221, 117, 107, 77, 233, 123, 201, 244, 18, 151,
      ...>   8, 255, 53, 137, 251, 197, 67, 25, 38, 95, 2, 62, 216, 131, 112, 116, 238, 180, 1, 3,
      ...>   1, 100, 1, 110, 1, 80>>
      ...> |> NetworkStats.deserialize()
      {
        %NetworkStats{
          stats: %{
            <<0>> => %{
              <<0, 0, 75, 23, 134, 64, 221, 117, 107, 77, 233, 123, 201, 244, 18, 151, 8, 255, 53,
                137, 251, 197, 67, 25, 38, 95, 2, 62, 216, 131, 112, 116, 238, 180>> => [
                %{latency: 100},
                %{latency: 110},
                %{latency: 80}
              ]
            }
          }
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<nb_subsets::16, rest::bitstring>>) do
    {stats, rest} = get_subsets_stats(rest, nb_subsets, %{})

    {
      %__MODULE__{stats: stats},
      rest
    }
  end

  defp get_subsets_stats(<<>>, _nb_subsets, acc), do: {acc, <<>>}
  defp get_subsets_stats(rest, nb_subsets, acc) when map_size(acc) == nb_subsets, do: {acc, rest}

  defp get_subsets_stats(<<subset::binary-size(1), data::bitstring>>, nb_subsets, acc) do
    {nb_stats, rest} = VarInt.get_value(data)
    {stats, rest} = get_stats(rest, nb_stats, %{})
    get_subsets_stats(rest, nb_subsets, Map.put(acc, subset, stats))
  end

  defp get_stats(<<>>, _nb_stats, acc), do: {acc, <<>>}
  defp get_stats(rest, nb_stats, acc) when map_size(acc) == nb_stats, do: {acc, rest}

  defp get_stats(data, nb_stats, acc) do
    {node_public_key, rest} = Utils.deserialize_public_key(data)
    {nb_latencies, rest} = VarInt.get_value(rest)
    {latencies, rest} = get_latencies(rest, nb_latencies, [])
    get_stats(rest, nb_stats, Map.put(acc, node_public_key, latencies))
  end

  defp get_latencies(rest, nb, acc) when length(acc) == nb, do: {Enum.reverse(acc), rest}
  defp get_latencies(<<>>, _, acc), do: {Enum.reverse(acc), <<>>}

  defp get_latencies(data, nb, acc) do
    {latency, rest} = VarInt.get_value(data)
    get_latencies(rest, nb, [%{latency: latency} | acc])
  end
end
