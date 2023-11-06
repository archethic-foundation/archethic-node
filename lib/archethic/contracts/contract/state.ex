defmodule Archethic.Contracts.Contract.State do
  @moduledoc """
  Module to manipulate the contract state
  """
  alias Archethic.Utils

  @current_serialization_version 1
  @max_compressed_state_size 256 * 1024
  @type_int 0
  @type_float 1
  @type_str 2
  @type_list 3
  @type_map 4
  @type_bool 5
  @type_nil 6

  @type t() :: map()
  @type encoded() :: binary()

  @spec empty() :: t()
  def empty(), do: %{}

  @spec empty?(state :: t()) :: boolean()
  def empty?(state), do: state == empty()

  @spec valid_size?(encoded_state :: encoded()) :: boolean()
  def valid_size?(encoded_state), do: byte_size(encoded_state) <= @max_compressed_state_size

  @doc """
  Serialize the given state
  """
  @spec serialize(t()) :: encoded()
  def serialize(state) do
    case @current_serialization_version do
      1 ->
        bitstr = do_serialize_v1(state)
        bitsize = bit_size(bitstr)

        # we keep track of the padding_bits added by wrap_binary
        # so we can ignore them in the deserialize function
        padding_bits =
          case rem(bitsize, 8) do
            0 ->
              0

            remainder ->
              8 - remainder
          end

        <<1::8, padding_bits::8, Utils.wrap_binary(bitstr)::binary>>
    end
  end

  @doc """
  Deserialize the state
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<1::8, padding_bits::8, rest::bitstring>>) do
    {state, <<_::integer-size(padding_bits), rest::bitstring>>} = do_deserialize_v1(rest)
    {state, rest}
  end

  ##################
  defp do_serialize_v1(nil) do
    <<@type_nil::8>>
  end

  defp do_serialize_v1(bool) when is_boolean(bool) do
    bool_bit = if bool, do: 1, else: 0
    <<@type_bool::8, bool_bit::1>>
  end

  defp do_serialize_v1(float) when is_float(float) do
    sign_bit = sign_to_bit(float)

    bin =
      float
      |> abs()
      |> Utils.to_bigint()
      |> Utils.VarInt.from_value()

    <<@type_float::8, sign_bit::1, bin::bitstring>>
  end

  defp do_serialize_v1(int) when is_integer(int) do
    sign_bit = sign_to_bit(int)
    bin = Utils.VarInt.from_value(int)

    <<@type_int::8, sign_bit::1, bin::bitstring>>
  end

  @max_byte_size 2 ** 32
  defp do_serialize_v1(bin) when is_binary(bin) do
    size = byte_size(bin)

    unless size < @max_byte_size do
      raise ArgumentError, message: "String cannot exceed #{@max_byte_size - 1} bytes"
    end

    <<@type_str::8, size::32, bin::bitstring>>
  end

  defp do_serialize_v1(map) when is_map(map) do
    count = map_size(map)

    Enum.reduce(map, <<@type_map::8, count::32>>, fn {k, v}, acc ->
      <<acc::bitstring, do_serialize_v1(k)::bitstring, do_serialize_v1(v)::bitstring>>
    end)
  end

  defp do_serialize_v1(list) when is_list(list) do
    count = length(list)

    Enum.reduce(list, <<@type_list::8, count::32>>, fn item, acc ->
      <<acc::bitstring, do_serialize_v1(item)::bitstring>>
    end)
  end

  ##################
  defp do_deserialize_v1(<<@type_nil::8, rest::bitstring>>) do
    {nil, rest}
  end

  defp do_deserialize_v1(<<@type_bool::8, bool_bit::1, rest::bitstring>>) do
    bool = bool_bit == 1
    {bool, rest}
  end

  defp do_deserialize_v1(<<@type_float::8, sign_bit::1, rest::bitstring>>) do
    {int, rest} = Utils.VarInt.get_value(rest)
    float = Utils.from_bigint(int) * bit_to_sign(sign_bit)
    {float, rest}
  end

  defp do_deserialize_v1(<<@type_int::8, sign_bit::1, rest::bitstring>>) do
    {int, rest} = Utils.VarInt.get_value(rest)
    int = int * bit_to_sign(sign_bit)
    {int, rest}
  end

  defp do_deserialize_v1(<<@type_str::8, size::32, rest::bitstring>>) do
    <<bin::binary-size(size), rest::bitstring>> = rest
    {bin, rest}
  end

  defp do_deserialize_v1(<<@type_map::8, 0::32, rest::bitstring>>) do
    {%{}, rest}
  end

  defp do_deserialize_v1(<<@type_map::8, count::32, rest::bitstring>>) do
    Enum.reduce(1..count, {%{}, rest}, fn _i, {map_acc, rest_acc} ->
      {key, rest_acc} = do_deserialize_v1(rest_acc)
      {value, rest_acc} = do_deserialize_v1(rest_acc)

      {Map.put(map_acc, key, value), rest_acc}
    end)
  end

  defp do_deserialize_v1(<<@type_list::8, 0::32, rest::bitstring>>) do
    {[], rest}
  end

  defp do_deserialize_v1(<<@type_list::8, count::32, rest::bitstring>>) do
    {list, rest} =
      Enum.reduce(1..count, {[], rest}, fn _i, {list_acc, rest_acc} ->
        {item, rest_acc} = do_deserialize_v1(rest_acc)

        {[item | list_acc], rest_acc}
      end)

    {Enum.reverse(list), rest}
  end

  defp sign_to_bit(num) when num >= 0, do: 1
  defp sign_to_bit(_num), do: 0

  defp bit_to_sign(0), do: -1
  defp bit_to_sign(1), do: 1
end
