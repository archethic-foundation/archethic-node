defmodule Uniris.OracleChainTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.OracleChain

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  import Mox

  test "verify/1 should decode the transaction content and verify the oracle correctness" do
    MockUCOPriceProvider
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => 0.20, "usd" => 0.12}}
    end)

    content =
      %{
        "last_updated_at" => DateTime.utc_now() |> DateTime.to_unix(),
        "data" => %{
          "uco" => %{"eur" => 0.20, "usd" => 0.12}
        }
      }
      |> Jason.encode!()

    {pub, pv} = Crypto.derive_keypair("seed", 0)
    {next_pub, _} = Crypto.derive_keypair("seed", 1)
    tx = Transaction.new(:oracle, %TransactionData{content: content}, pv, pub, next_pub)
    assert true == OracleChain.verify?(tx)
  end

  test "verify_summary/1 should decode the transaction content and verify with the given address" do
    last_update_at = DateTime.utc_now() |> DateTime.to_unix()

    {pub, pv} = Crypto.derive_keypair("seed", 0)
    {next_pub, _} = Crypto.derive_keypair("seed", 1)

    previous_address = Crypto.hash(pub)

    MockDB
    |> stub(:get_transaction, fn
      ^previous_address, _ ->
        {:error, :transaction_not_exists}

      _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             content:
               %{
                 "last_updated_at" => last_update_at,
                 "data" => %{
                   "uco" => %{"eur" => 0.20, "usd" => 0.12}
                 }
               }
               |> Jason.encode!()
           }
         }}
    end)

    content =
      %{
        "data" => %{
          last_update_at => %{
            "uco" => %{"eur" => 0.20, "usd" => 0.12}
          }
        }
      }
      |> Jason.encode!()

    tx = Transaction.new(:oracle_summary, %TransactionData{content: content}, pv, pub, next_pub)
    assert true == OracleChain.verify_summary?(tx)
  end
end
