defmodule Archethic.Utils.TypedEncodingTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Archethic.Utils
  alias Archethic.Utils.TypedEncoding

  property "symmetric encoding/decoding of typed data" do
    check all(
            data <-
              StreamData.one_of([
                StreamData.integer(),
                float_gen(),
                StreamData.string(:alphanumeric),
                StreamData.boolean(),
                StreamData.constant(nil),
                map_gen(),
                list_gen()
              ])
          ) do
      assert {^data, ""} =
               data
               |> TypedEncoding.serialize(:extended)
               |> TypedEncoding.deserialize(:extended)

      assert {^data, ""} =
               data
               |> TypedEncoding.serialize(:compact)
               |> TypedEncoding.deserialize(:compact)
    end
  end

  defp map_gen do
    StreamData.tree(
      StreamData.one_of([
        StreamData.integer(),
        float_gen(),
        StreamData.string(:alphanumeric),
        StreamData.boolean(),
        StreamData.constant(nil),
        list_gen()
      ]),
      fn nested_generator ->
        StreamData.map_of(StreamData.string(:alphanumeric), nested_generator)
      end
    )
  end

  defp list_gen do
    StreamData.tree(
      StreamData.one_of([
        StreamData.integer(),
        float_gen(),
        StreamData.string(:alphanumeric),
        StreamData.boolean(),
        StreamData.constant(nil)
      ]),
      &StreamData.list_of/1
    )
  end

  defp float_gen do
    StreamData.map(StreamData.float(), fn float ->
      sign_factor =
        if float > 0 do
          1
        else
          -1
        end

      float
      |> abs()
      |> Utils.to_bigint()
      |> Utils.from_bigint()
      |> Kernel.*(sign_factor)
    end)
  end
end
