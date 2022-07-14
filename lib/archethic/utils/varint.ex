defmodule Archethic.Utils.VarInt do
  @moduledoc """
    VarInt is a Module for support of multi-byte length integers
  """

  defstruct [:bytes, :value]

  @type t :: %__MODULE__{
          bytes: non_neg_integer(),
          value: non_neg_integer()
        }

  def from_value(value) do
    bytes = value |> min_bytes_to_store()

    %__MODULE__{
      bytes: bytes,
      value: value
    }
  end

  def from_map(varint = %{}) do
    %__MODULE__{
      bytes: Map.get(varint, :bytes),
      value: Map.get(varint, :value)
    }
  end

  @spec min_bytes_to_store(integer()) :: integer()
  defp min_bytes_to_store(value) do
    # Since values go from
    # 1*8 => 2^8 => 256
    # 2*8 => 16 => 2^16 => 65536
    # 3*8 => 24 => 2^24 => 16777216
    ranges =
      1..256
      |> Enum.with_index(fn element, index -> {index + 1, element} end)
      |> Enum.map(fn {i, x} -> {i, Integer.pow(2, 8 * x)} end)

    # Since Range is in sorted order, first find would be the least amount of bytes required range.
    {bytes, _range} = ranges |> Enum.find(fn {_bytes, range_max} -> value < range_max end)
    bytes
  end

  @spec serialize(__MODULE__.t()) :: <<_::8, _::_*8>>
  def serialize(%__MODULE__{bytes: bytes, value: value}) do
    <<bytes::8>> <> <<value::size(bytes)-unit(8)>>
  end

  @spec deserialize(bitstring()) :: __MODULE__.t()
  def deserialize(data) do
    <<bytes::8, rest::bitstring>> = data

    if byte_size(rest) != bytes do
      raise ArgumentError,
        message:
          "the argument value is invalid, Byte Size Supplied: #{bytes}, Bytes found : #{byte_size(rest)}. Should be equal."
    end

    <<value::size(bytes)-unit(8)>> = rest

    %__MODULE__{
      bytes: bytes,
      value: value
    }
  end

  @spec get_value(bitstring()) :: %{value: integer(), rest: bitstring()}
  def get_value(data) do
    <<bytes::8, rest::bitstring>> = data

    <<value::size(bytes)-unit(8), rest::bitstring>> = rest

    %{
      value: value,
      rest: rest
    }
  end
end
