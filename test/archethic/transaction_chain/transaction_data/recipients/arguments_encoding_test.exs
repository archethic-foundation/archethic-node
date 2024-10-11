defmodule Archethic.TransactionChain.TransactionData.Recipient.ArgumentsEncodingTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Archethic.TransactionChain.TransactionData.Recipient.ArgumentsEncoding

  property "symmetric encoding/decoding of recipients arguments as list" do
    check all(
            args <-
              StreamData.list_of(
                StreamData.one_of([
                  StreamData.integer(),
                  StreamData.string(:alphanumeric),
                  StreamData.boolean(),
                  StreamData.constant(nil)
                ])
              )
          ) do
      assert {^args, ""} =
               args
               |> ArgumentsEncoding.serialize(:compact, 3)
               |> ArgumentsEncoding.deserialize(:compact, 3)

      assert {^args, ""} =
               args
               |> ArgumentsEncoding.serialize(:extended, 3)
               |> ArgumentsEncoding.deserialize(:extended, 3)
    end
  end

  property "symmetric encoding/decoding of recipients arguments as map" do
    check all(
            args <-
              StreamData.map_of(
                StreamData.string(:alphanumeric),
                StreamData.one_of([
                  StreamData.integer(),
                  StreamData.string(:alphanumeric),
                  StreamData.boolean(),
                  StreamData.constant(nil)
                ])
              )
          ) do
      assert {^args, ""} =
               args
               |> ArgumentsEncoding.serialize(
                 :compact,
                 ArchethicCase.current_transaction_version()
               )
               |> ArgumentsEncoding.deserialize(
                 :compact,
                 ArchethicCase.current_transaction_version()
               )

      assert {^args, ""} =
               args
               |> ArgumentsEncoding.serialize(
                 :extended,
                 ArchethicCase.current_transaction_version()
               )
               |> ArgumentsEncoding.deserialize(
                 :extended,
                 ArchethicCase.current_transaction_version()
               )
    end
  end
end
