defmodule Archethic.OracleChain.ServicesTest do
  use ExUnit.Case

  alias Archethic.OracleChain.Services
  alias ArchethicCache.HydratingCache
  import Mox

  describe "fetch_new_data/1" do
    test "should return the new data when no previous content" do
      HydratingCache.register_function(
        HydratingCache.UcoPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
        30_000,
        :infinity
      )

      HydratingCache.register_function(
        HydratingCache.UcoPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
        30_000,
        :infinity
      )

      HydratingCache.register_function(
        HydratingCache.UcoPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
        30_000,
        :infinity
      )

      assert %{uco: %{"eur" => 0.20, "usd" => 0.12}} = Services.fetch_new_data()
    end

    test "should not return the new data when the previous content is the same" do
      HydratingCache.register_function(
        HydratingCache.UcoPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
        30_000,
        :infinity
      )

      HydratingCache.register_function(
        HydratingCache.UcoPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
        30_000,
        :infinity
      )

      HydratingCache.register_function(
        HydratingCache.UcoPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
        30_000,
        :infinity
      )

      assert %{} = Services.fetch_new_data(%{uco: %{"eur" => 0.20, "usd" => 0.12}})
    end

    test "should return the new data when the previous content is not the same" do
      HydratingCache.register_function(
        HydratingCache.UcoPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
        30_000,
        :infinity
      )

      HydratingCache.register_function(
        HydratingCache.UcoPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
        30_000,
        :infinity
      )

      HydratingCache.register_function(
        HydratingCache.UcoPrice,
        fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
        Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
        30_000,
        :infinity
      )

      assert %{uco: %{"eur" => 0.20, "usd" => 0.12}} =
               Services.fetch_new_data(%{"uco" => %{"eur" => 0.19, "usd" => 0.15}})
    end
  end

  test "verify_correctness?/1 should true when the data is correct" do
    HydratingCache.register_function(
      HydratingCache.UcoPrice,
      fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      HydratingCache.UcoPrice,
      fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap,
      30_000,
      :infinity
    )

    HydratingCache.register_function(
      HydratingCache.UcoPrice,
      fn -> {:ok, %{"usd" => [0.12], "eur" => [0.20]}} end,
      Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika,
      30_000,
      :infinity
    )

    assert true == Services.verify_correctness?(%{"uco" => %{"eur" => 0.20, "usd" => 0.12}})
  end

  def fetch(values) do
    values
  end
end
