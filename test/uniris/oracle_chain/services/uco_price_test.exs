defmodule Uniris.OracleChain.Services.UCOPriceTest do
  use ExUnit.Case

  alias Uniris.OracleChain.Services.UCOPrice

  import Mox

  test "fetch/0 should retrieve some data and build a map with the oracle name in it" do
    MockUCOPriceProvider
    |> expect(:fetch, fn pairs ->
      res =
        Enum.map(pairs, fn pair ->
          {pair, :rand.uniform_real()}
        end)
        |> Enum.into(%{})

      {:ok, res}
    end)

    assert {:ok, %{"eur" => _, "usd" => _}} = UCOPrice.fetch()
  end

  describe "verify/1" do
    test "should return true if the prices are the good one" do
      MockUCOPriceProvider
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => 0.20, "usd" => 0.12}}
      end)

      assert true == UCOPrice.verify?(%{"eur" => 0.20, "usd" => 0.12})
    end

    test "should return false if the prices are not the good one" do
      MockUCOPriceProvider
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => 0.20, "usd" => 0.12}}
      end)

      assert false == UCOPrice.verify?(%{"eur" => 0.10, "usd" => 0.14})
    end
  end
end
