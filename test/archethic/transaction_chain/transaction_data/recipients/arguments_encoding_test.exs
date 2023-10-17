defmodule Archethic.TransactionChain.TransactionData.Recipient.ArgumentsEncodingTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Archethic.TransactionChain.TransactionData.Recipient.ArgumentsEncoding

  property "symmetric encoding/decoding of recipients arguments" do
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
               |> ArgumentsEncoding.serialize(:compact)
               |> ArgumentsEncoding.deserialize(:compact)

      assert {^args, ""} =
               args
               |> ArgumentsEncoding.serialize(:extended)
               |> ArgumentsEncoding.deserialize(:extended)
    end
  end
end
