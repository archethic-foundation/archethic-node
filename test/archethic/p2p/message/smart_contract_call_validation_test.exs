defmodule Archethic.P2P.Message.SmartContractCallValidationTest do
  use ExUnit.Case

  alias Archethic.P2P.Message.SmartContractCallValidation

  doctest SmartContractCallValidation

  test "serialization/deserialization" do
    msg = %SmartContractCallValidation{
      status: :ok,
      fee: 186_435_476,
      latest_validation_time: DateTime.utc_now() |> DateTime.truncate(:millisecond)
    }

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()

    msg = %SmartContractCallValidation{
      status: {:error, :transaction_not_exists},
      fee: 0,
      latest_validation_time: DateTime.utc_now() |> DateTime.truncate(:millisecond)
    }

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()

    msg = %SmartContractCallValidation{
      status: {:error, :invalid_execution},
      fee: 0,
      latest_validation_time: DateTime.from_unix!(0, :millisecond)
    }

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()
  end
end
