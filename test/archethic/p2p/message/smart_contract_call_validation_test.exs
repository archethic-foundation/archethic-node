defmodule Archethic.P2P.Message.SmartContractCallValidationTest do
  use ExUnit.Case

  alias Archethic.P2P.Message.SmartContractCallValidation

  doctest SmartContractCallValidation

  describe "serialization deserialization" do
    test "should encode decode properly without reason" do
      msg = %SmartContractCallValidation{valid?: true, fee: 186_435_476}

      assert {^msg, <<>>} =
               msg
               |> SmartContractCallValidation.serialize()
               |> SmartContractCallValidation.deserialize()

      msg = %SmartContractCallValidation{valid?: false, fee: 104}

      assert {^msg, <<>>} =
               msg
               |> SmartContractCallValidation.serialize()
               |> SmartContractCallValidation.deserialize()
    end

    test "should encode decode properly with a reason" do
      msg = %SmartContractCallValidation{valid?: false, fee: 104, reason: "inacceptable value"}

      assert {^msg, <<>>} =
               msg
               |> SmartContractCallValidation.serialize()
               |> SmartContractCallValidation.deserialize()
    end
  end
end
