defmodule Archethic.OracleChainTest do
  use ArchethicCase

  alias Archethic.OracleChain

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  import Mox

  test "valid_services_content?/1 should verify the oracle transaction's content correctness" do
    MockUCOPriceProvider
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.20], "usd" => [0.12]}}
    end)

    content =
      %{
        "uco" => %{"eur" => 0.20, "usd" => 0.12}
      }
      |> Jason.encode!()

    assert true == OracleChain.valid_services_content?(content)
  end

  test "valid_summary?/2 should validate the summary content" do
    last_update_at = DateTime.utc_now() |> DateTime.to_unix()

    content =
      %{
        last_update_at => %{
          "uco" => %{"eur" => 0.20, "usd" => 0.12}
        }
      }
      |> Jason.encode!()

    chain = [
      %Transaction{
        type: :oracle,
        data: %TransactionData{
          content:
            %{
              "uco" => %{"eur" => 0.20, "usd" => 0.12}
            }
            |> Jason.encode!()
        },
        validation_stamp: %ValidationStamp{
          timestamp: DateTime.from_unix!(last_update_at)
        }
      }
    ]

    assert true == OracleChain.valid_summary?(content, chain)
  end
end
