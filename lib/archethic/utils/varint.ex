defmodule Archethic.Utils.VarInt do
  @moduledoc """
    VarInt is a Module for support of multi-byte length integers
  """

  @spec from_value(integer()) :: bitstring()
  def from_value(value) do
    bytes = value |> min_bytes_to_store()
    <<bytes::8, value::bytes*8>>
  end

  @spec min_bytes_to_store(integer()) :: integer()
  defp min_bytes_to_store(value) do
    # Since values go from
    # 1*8 => 2^8 => 255 ~BYTES=1
    # 2*8 => 16 => 2^16 => 65535 ~BYTES=2
    # 3*8 => 24 => 2^24 => 16777215 ~BYTES=3
    1..255 |> Enum.find(fn x -> value < Integer.pow(2, 8 * x) end)
  end

  @spec get_value(bitstring()) :: {integer(), bitstring()}
  def get_value(data) do
    <<bytes::8, rest::bitstring>> = data
    <<value::bytes*8, rest::bitstring>> = rest

    {
      value,
      rest
    }
  end
end
