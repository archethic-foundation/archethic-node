defmodule Archethic.P2P.Message.SmartContractCallValidationTest do
  use ExUnit.Case

  alias Archethic.P2P.Message.SmartContractCallValidation

  doctest SmartContractCallValidation

  test "serialization/deserialization" do
    msg = %SmartContractCallValidation{status: :ok, fee: 186_435_476}

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()

    msg = %SmartContractCallValidation{status: {:error, :transaction_not_exists}, fee: 0}

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()

    msg = %SmartContractCallValidation{status: {:error, :invalid_execution}, fee: 0}

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()
  end
end
