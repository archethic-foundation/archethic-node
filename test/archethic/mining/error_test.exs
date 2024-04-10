defmodule Archethic.Mining.ErrorTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Archethic.Mining.Error

  alias Archethic.Utils

  describe "new/2" do
    test "should create new error struc for all possible error" do
      list_errors()
      |> Enum.each(fn error ->
        assert %Error{} = Error.new(error)
      end)
    end

    test "should return different code for each error" do
      error_codes =
        list_errors()
        |> Enum.reduce([], fn error, acc ->
          %Error{code: code} = Error.new(error)
          refute Enum.member?(acc, code)
          [code | acc]
        end)

      assert length(error_codes) == length(list_errors())
    end

    property "should create error with data" do
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
        %Error{data: ^data} = Error.new(:invalid_recipients_execution, data)
      end
    end
  end

  property "serialization" do
    check all(
            error <- StreamData.one_of(list_errors()),
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
      error = Error.new(error, data)
      assert {error, ""} == error |> Error.serialize() |> Error.deserialize()
    end
  end

  test "to_stamp_error/1 should convert error into stamp error" do
    list_stamp_errors()
    |> Enum.each(fn error ->
      assert error == error |> Error.new() |> Error.to_stamp_error()
    end)
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

  defp list_stamp_errors() do
    [
      :invalid_pending_transaction,
      :invalid_inherit_constraints,
      :insufficient_funds,
      :invalid_contract_execution,
      :invalid_recipients_execution,
      :recipients_not_distinct,
      :invalid_contract_context_inputs
    ]
  end

  defp list_errors() do
    list_stamp_errors() ++ [:timeout, :consensus_not_reached, :transaction_in_mining]
  end
end
