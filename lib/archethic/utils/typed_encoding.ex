defmodule Archethic.Utils.TypedEncoding do
  @moduledoc """
  Handle encoding of typed data
  """

  @type_int 0
  @type_float 1
  @type_str 2
  @type_list 3
  @type_map 4
  @type_bool 5
  @type_nil 6

  @type arg() :: number() | boolean() | binary() | list() | map() | nil

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @spec serialize(arg(), bit_size :: pos_integer()) :: bitstring()
  def serialize(int, bit_size) when is_integer(int) do
    sign_bit = sign_to_bit(int)

    bin =
      int
      |> abs()
      |> VarInt.from_value()

    <<@type_int::8, sign_bit::integer-size(bit_size), bin::bitstring>>
  end

  def serialize(float, bit_size) when is_float(float) do
    sign_bit = sign_to_bit(float)

    bin =
      float
      |> abs()
      |> Utils.to_bigint()
      |> VarInt.from_value()

    <<@type_float::8, sign_bit::integer-size(bit_size), bin::bitstring>>
  end

  def serialize(bin, _bit_size) when is_binary(bin) do
    size = byte_size(bin)
    size_bin = VarInt.from_value(size)
    <<@type_str::8, size_bin::binary, bin::bitstring>>
  end

  def serialize(list, bit_size) when is_list(list) do
    size = length(list)
    size_bin = VarInt.from_value(size)

    Enum.reduce(list, <<@type_list::8, size_bin::binary>>, fn item, acc ->
      <<acc::bitstring, serialize(item, bit_size)::bitstring>>
    end)
  end

  def serialize(map, bit_size) when is_map(map) do
    size = map_size(map)
    size_bin = VarInt.from_value(size)

    Enum.reduce(map, <<@type_map::8, size_bin::binary>>, fn {k, v}, acc ->
      <<acc::bitstring, serialize(k, bit_size)::bitstring, serialize(v, bit_size)::bitstring>>
    end)
  end

  def serialize(bool, bit_size) when is_boolean(bool) do
    bool_bit = if bool, do: 1, else: 0
    <<@type_bool::8, bool_bit::integer-size(bit_size)>>
  end

  def serialize(nil, _bit_size) do
    <<@type_nil::8>>
  end

  defp sign_to_bit(num) when num >= 0, do: 1
  defp sign_to_bit(_num), do: 0

  @spec deserialize(binary :: bitstring(), bit_size :: pos_integer()) ::
          {list(arg()), bitstring()}
  def deserialize(<<@type_int::8, rest::bitstring>>, bit_size) do
    <<sign_bit::integer-size(bit_size), rest::bitstring>> = rest
    {int, rest} = VarInt.get_value(rest)
    int = int * bit_to_sign(sign_bit)
    {int, rest}
  end

  def deserialize(<<@type_float::8, rest::bitstring>>, bit_size) do
    <<sign_bit::integer-size(bit_size), rest::bitstring>> = rest
    {int, rest} = VarInt.get_value(rest)
    float = Utils.from_bigint(int) * bit_to_sign(sign_bit)
    {float, rest}
  end

  def deserialize(<<@type_str::8, rest::bitstring>>, _bit_size) do
    {size, rest} = VarInt.get_value(rest)
    <<bin::binary-size(size), rest::bitstring>> = rest
    {bin, rest}
  end

  def deserialize(<<@type_list::8, rest::bitstring>>, bit_size) do
    {size, rest} = VarInt.get_value(rest)

    case size do
      0 ->
        {[], rest}

      _ ->
        {list, rest} =
          Enum.reduce(1..size, {[], rest}, fn _i, {list_acc, rest_acc} ->
            {item, rest_acc} = deserialize(rest_acc, bit_size)

            {[item | list_acc], rest_acc}
          end)

        {Enum.reverse(list), rest}
    end
  end

  def deserialize(<<@type_map::8, rest::bitstring>>, bit_size) do
    {size, rest} = VarInt.get_value(rest)

    case size do
      0 ->
        {%{}, rest}

      _ ->
        Enum.reduce(1..size, {%{}, rest}, fn _i, {map_acc, rest_acc} ->
          {key, rest_acc} = deserialize(rest_acc, bit_size)
          {value, rest_acc} = deserialize(rest_acc, bit_size)

          {Map.put(map_acc, key, value), rest_acc}
        end)
    end
  end

  def deserialize(<<@type_bool::8, rest::bitstring>>, bit_size) do
    <<bool_bit::integer-size(bit_size), rest::bitstring>> = rest
    bool = bool_bit == 1
    {bool, rest}
  end

  def deserialize(<<@type_nil::8, rest::bitstring>>, _bit_size), do: {nil, rest}

  defp bit_to_sign(0), do: -1
  defp bit_to_sign(1), do: 1
end
