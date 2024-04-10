defmodule Archethic.P2P.Message.SmartContractCallValidationTest do
  use ExUnit.Case

  alias Archethic.Contracts.Contract.Failure
  alias Archethic.P2P.Message.SmartContractCallValidation

  doctest SmartContractCallValidation

  test "serialization deserialization" do
    last_chain_sync_date = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    msg = %SmartContractCallValidation{
      status: :ok,
      fee: 186_435_476,
      last_chain_sync_date: last_chain_sync_date
    }

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()

    msg = %SmartContractCallValidation{
      status: {:error, :transaction_not_exists},
      fee: 0,
      last_chain_sync_date: last_chain_sync_date
    }

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()

    msg = %SmartContractCallValidation{
      status: {:error, :invalid_condition, "content"},
      fee: 0,
      last_chain_sync_date: last_chain_sync_date
    }

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()

    failure = %Failure{user_friendly_error: "Friendly error", error: :execution_timeout}

    msg = %SmartContractCallValidation{
      status: {:error, :invalid_execution, failure},
      fee: 0,
      last_chain_sync_date: last_chain_sync_date
    }

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()

    failure = %Failure{
      user_friendly_error: "Friendly error",
      error: :contract_throw,
      data: %{"code" => 123, "message" => "Throw error message", "data" => nil}
    }

    msg = %SmartContractCallValidation{
      status: {:error, :invalid_execution, failure},
      fee: 0,
      last_chain_sync_date: last_chain_sync_date
    }

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()

    failure = %Failure{
      user_friendly_error: "Friendly error",
      error: :contract_throw,
      data: %{"code" => 123, "message" => "Throw error message", "data" => ["list", "value"]}
    }

    msg = %SmartContractCallValidation{
      status: {:error, :invalid_execution, failure},
      fee: 0,
      last_chain_sync_date: last_chain_sync_date
    }

    assert {^msg, <<>>} =
             msg
             |> SmartContractCallValidation.serialize()
             |> SmartContractCallValidation.deserialize()
  end
end
