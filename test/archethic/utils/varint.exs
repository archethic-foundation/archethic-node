defmodule VarIntTest do
  use ExUnit.Case
  alias Archethic.Utils.VarInt

  doctest VarInt

  test "should encode 8 bit number" do
    assert VarInt.from_value(25) == <<1::8, 25::8>>
  end

  test "should deserialize 8 bit encoded bitstring" do
    data = <<3, 2, 184, 169>>
    assert {178_345, <<>>} == data |> VarInt.get_value()
  end

  test "should encode and decode randomly 100 integers" do
    numbers =
      1..100
      |> Enum.map(fn x -> Integer.pow(1..2048 |> Enum.random(), x) end)

    # Encode the numbers in bitstrings
    struct_nums = numbers |> Enum.map(fn x -> x |> VarInt.from_value() end)

    # Deserialize the bitstrings to numbers
    decoded_numbers =
      serialized_numbers
      |> Enum.map(fn x ->
        {value, _} = x |> VarInt.get_value()
        value
      end)

    assert numbers -- decoded_numbers == []
  end

  test "Should Return the Correct Rest" do
    data = <<1, 34>>
    rest = <<2, 3>>

    {value, returned_rest} = VarInt.get_value(data <> rest)

    assert rest == returned_rest
  end
end
