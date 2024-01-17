defmodule Archethic.P2P.Message.DashboardData do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @enforce_keys [:buckets]
  defstruct [:buckets]

  @type t :: %__MODULE__{
          buckets: %{DateTime.t() => list({Crypto.prepended_hash(), pos_integer()})}
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{buckets: buckets}) do
    buckets_serialized =
      buckets
      # do not remove this sort_by because messages are signed
      |> Enum.sort_by(fn {datetime, _} -> datetime end, {:asc, DateTime})
      |> Enum.reduce(<<>>, fn {datetime, duration_by_address}, acc ->
        count = VarInt.from_value(length(duration_by_address))

        durations_serialized =
          Enum.reduce(duration_by_address, <<>>, fn {address, duration}, acc ->
            <<acc::bitstring, address::bitstring, VarInt.from_value(duration)::bitstring>>
          end)

        acc <>
          <<DateTime.to_unix(datetime)::32, count::bitstring, durations_serialized::bitstring>>
      end)

    buckets_count = VarInt.from_value(map_size(buckets))

    <<buckets_count::bitstring, buckets_serialized::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {buckets_count, rest} = VarInt.get_value(rest)
    {buckets, rest} = deserialize_buckets(buckets_count, %{}, rest)

    {%__MODULE__{buckets: buckets}, rest}
  end

  defp deserialize_buckets(0, acc, rest), do: {acc, rest}

  defp deserialize_buckets(n, acc, rest) do
    <<timestamp::32, rest::bitstring>> = rest

    {durations_count, rest} = VarInt.get_value(rest)
    {durations, rest} = deserialize_durations(durations_count, [], rest)

    datetime = DateTime.from_unix!(timestamp)

    deserialize_buckets(n - 1, Map.put(acc, datetime, durations), rest)
  end

  defp deserialize_durations(0, acc, rest), do: {Enum.reverse(acc), rest}

  defp deserialize_durations(n, acc, rest) do
    {address, rest} = Utils.deserialize_address(rest)
    {duration, rest} = VarInt.get_value(rest)
    deserialize_durations(n - 1, [{address, duration} | acc], rest)
  end
end
