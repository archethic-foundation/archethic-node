defmodule Archethic.OracleChain.Services.UCOPriceTest do
  use ExUnit.Case

  alias Archethic.OracleChain.Services.UCOPrice

  alias ArchethicCache.HydratingCache

  test "fetch/0 should retrieve some data and build a map with the oracle name in it" do
    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
      30_000,
      :infinity
    )

    assert {:ok, %{"eur" => _, "usd" => _}} = UCOPrice.fetch()
  end

  test "fetch/0 should retrieve some data and build a map with the oracle name in it and keep the precision to 5" do
    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"eur" => [0.123456789], "usd" => [0.123454789]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"eur" => [0.123456789], "usd" => [0.123454789]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"eur" => [0.123456789], "usd" => [0.123454789]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
      30_000,
      :infinity
    )

    assert {:ok, %{"eur" => 0.12346, "usd" => 0.12345}} = UCOPrice.fetch()
  end

  describe "verify/1" do
    test "should return true if the prices are the good one" do
      HydratingCache.register_function(
        Archethic.OracleChain.Services.UCOPrice,
        fn -> {:ok, %{"eur" => [0.10], "usd" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
        30_000,
        :infinity
      )

      HydratingCache.register_function(
        Archethic.OracleChain.Services.UCOPrice,
        fn -> {:ok, %{"eur" => [0.20], "usd" => [0.30]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
        30_000,
        :infinity
      )

      HydratingCache.register_function(
        Archethic.OracleChain.Services.UCOPrice,
        fn -> {:ok, %{"eur" => [0.30], "usd" => [0.40]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
        30_000,
        :infinity
      )

      assert {:ok, %{"eur" => 0.20, "usd" => 0.30}} == UCOPrice.fetch()
    end

    test "should return false if the prices have deviated" do
      HydratingCache.register_function(
        Archethic.OracleChain.Services.UCOPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
        30_000,
        :infinity
      )

      HydratingCache.register_function(
        Archethic.OracleChain.Services.UCOPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
        30_000,
        :infinity
      )

      HydratingCache.register_function(
        Archethic.OracleChain.Services.UCOPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
        30_000,
        :infinity
      )

      assert false == UCOPrice.verify?(%{"eur" => 0.10, "usd" => 0.14})
    end
  end

  test "should return the median value when multiple providers queried" do
    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.20], "eur" => [0.20]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.30], "eur" => [0.30]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.40], "eur" => [0.40]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
      30_000,
      :infinity
    )

    assert true == UCOPrice.verify?(%{"eur" => 0.30, "usd" => 0.30})
  end

  test "should return the average of median values when a even number of providers queried" do
    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.10], "eur" => [0.10]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.20, 0.30], "eur" => [0.20, 0.30]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.40], "eur" => [0.40]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
      30_000,
      :infinity
    )

    assert {:ok, %{"eur" => 0.25, "usd" => 0.25}} == UCOPrice.fetch()
  end

  test "verify?/1 should return false when no data are returned from all providers" do
    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [], "eur" => []}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [], "eur" => []}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [], "eur" => []}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
      30_000,
      :infinity
    )

    assert false == UCOPrice.verify?(%{})
  end

  test "should report values even if a provider returns an error" do
    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.10], "eur" => [0.10]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
      30_000,
      :infinity
    )

    ## If service returns an error, old value will be returned
    ## we are so inserting a previous value
    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn ->
        {:ok, %{"usd" => [0.20], "eur" => [0.20]}}
      end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:error, :error_message} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.30], "eur" => [0.30]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
      30_000,
      :infinity
    )

    assert {:ok, %{"eur" => 0.20, "usd" => 0.20}} = UCOPrice.fetch()
  end

  test "should handle a service timing out" do
    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.10], "eur" => [0.10]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn ->
        {:ok, %{"usd" => [0.20], "eur" => [0.20]}}
      end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn ->
        :timer.sleep(5_000)
        {:ok, {:error, :error_message}}
      end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      Archethic.OracleChain.Services.UCOPrice,
      fn -> {:ok, %{"usd" => [0.30], "eur" => [0.30]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
      30_000,
      :infinity
    )

    assert {:ok, %{"eur" => 0.20, "usd" => 0.20}} == UCOPrice.fetch()
  end

  def fetch(values) do
    values
  end
end
