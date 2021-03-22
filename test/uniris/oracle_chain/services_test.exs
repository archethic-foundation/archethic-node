defmodule Uniris.OracleChain.ServicesTest do
  use ExUnit.Case

  alias Uniris.OracleChain.Services

  import Mox

  describe "fetch_new_data/1" do
    test "should return the new data when no previous content" do
      MockUCOPriceProvider
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => 0.20, "usd" => 0.12}}
      end)

      assert %{uco: %{"eur" => 0.20, "usd" => 0.12}} = Services.fetch_new_data()
    end

    test "should not return the new data when the previous content is the same" do
      MockUCOPriceProvider
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => 0.20, "usd" => 0.12}}
      end)

      assert %{} = Services.fetch_new_data(%{uco: %{"eur" => 0.20, "usd" => 0.12}})
    end

    test "should return the new data when the previous content is not the same" do
      MockUCOPriceProvider
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => 0.20, "usd" => 0.12}}
      end)

      assert %{uco: %{"eur" => 0.20, "usd" => 0.12}} =
               Services.fetch_new_data(%{"uco" => %{"eur" => 0.19, "usd" => 0.15}})
    end
  end

  test "verify_correctness?/1 should true when the data is correct" do
    MockUCOPriceProvider
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => 0.20, "usd" => 0.12}}
    end)

    assert true == Services.verify_correctness?(%{"uco" => %{"eur" => 0.20, "usd" => 0.12}})
  end
end
