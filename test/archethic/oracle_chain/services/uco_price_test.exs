defmodule Archethic.OracleChain.Services.UCOPriceTest do
  use ExUnit.Case

  alias Archethic.OracleChain.Services.UCOPrice

  alias Archethic.Utils.HydratingCache

  test "fetch/0 should retrieve some data and build a map with the oracle name in it" do
    _ =
      HydratingCache.start_link(:uco_service, [
        {MockUCOPriceProvider1, __MODULE__, :fetch, [{:ok, %{"eur" => [0.20], "usd" => [0.12]}}],
         30_000, :infinity},
        {MockUCOPriceProvider2, __MODULE__, :fetch, [{:ok, %{"eur" => [0.20], "usd" => [0.12]}}],
         30_000, :infinity},
        {MockUCOPriceProvider3, __MODULE__, :fetch, [{:ok, %{"eur" => [0.20], "usd" => [0.12]}}],
         30_000, :infinity}
      ])

    assert {:ok, %{"eur" => _, "usd" => _}} = UCOPrice.fetch()
  end

  test "fetch/0 should retrieve some data and build a map with the oracle name in it and keep the precision to 5" do
    _ =
      HydratingCache.start_link(:uco_service, [
        {MockUCOPriceProvider1, __MODULE__, :fetch,
         [{:ok, %{"eur" => [0.123456789], "usd" => [0.123454789]}}], 30_000, :infinity},
        {MockUCOPriceProvider2, __MODULE__, :fetch,
         [{:ok, %{"eur" => [0.123456789], "usd" => [0.123454789]}}], 30_000, :infinity},
        {MockUCOPriceProvider3, __MODULE__, :fetch,
         [{:ok, %{"eur" => [0.123456789], "usd" => [0.123454789]}}], 30_000, :infinity}
      ])

    assert {:ok, %{"eur" => 0.12346, "usd" => 0.12345}} = UCOPrice.fetch()
  end

  describe "verify/1" do
    test "should return true if the prices are the good one" do
      _ =
        HydratingCache.start_link(:uco_service, [
          {MockUCOPriceProvider1, __MODULE__, :fetch,
           [{:ok, %{"eur" => [0.20], "usd" => [0.11]}}], 30_000, :infinity},
          {MockUCOPriceProvider2, __MODULE__, :fetch,
           [{:ok, %{"eur" => [0.30, 0.40], "usd" => [0.12, 0.13]}}], 30_000, :infinity},
          {MockUCOPriceProvider3, __MODULE__, :fetch,
           [{:ok, %{"eur" => [0.50], "usd" => [0.14]}}], 30_000, :infinity}
        ])

      assert {:ok, %{"eur" => 0.35, "usd" => 0.125}} == UCOPrice.fetch()
    end

    test "should return false if the prices have deviated" do
      _ =
        HydratingCache.start_link(:uco_service, [
          {MockUCOPriceProvider1, __MODULE__, :fetch,
           [{:ok, %{"eur" => [0.20], "usd" => [0.12]}}], 30_000, :infinity},
          {MockUCOPriceProvider2, __MODULE__, :fetch,
           [{:ok, %{"eur" => [0.20], "usd" => [0.12]}}], 30_000, :infinity},
          {MockUCOPriceProvider3, __MODULE__, :fetch,
           [{:ok, %{"eur" => [0.20], "usd" => [0.12]}}], 30_000, :infinity}
        ])

      assert false == UCOPrice.verify?(%{"eur" => 0.10, "usd" => 0.14})
    end
  end

  test "should return the median value when multiple providers queried" do
    _ =
      HydratingCache.start_link(:uco_service, [
        {MockUCOPriceProvider1, __MODULE__, :fetch, [{:ok, %{"eur" => [0.20], "usd" => [0.12]}}],
         30_000, :infinity},
        {MockUCOPriceProvider2, __MODULE__, :fetch, [{:ok, %{"eur" => [0.30], "usd" => [0.12]}}],
         30_000, :infinity},
        {MockUCOPriceProvider3, __MODULE__, :fetch, [{:ok, %{"eur" => [0.40], "usd" => [0.12]}}],
         30_000, :infinity}
      ])

    assert true == UCOPrice.verify?(%{"eur" => 0.30, "usd" => 0.12})
  end

  test "should return the average of median values when a even number of providers queried" do
    ## Define a fourth mock to have even number of mocks
    Mox.defmock(MockUCOPriceProvider4,
      for: Archethic.OracleChain.Services.UCOPrice.Providers.Impl
    )
    _ =
      HydratingCache.start_link(:uco_service, [
        {MockUCOPriceProvider1, __MODULE__, :fetch, [{:ok, %{"eur" => [0.20], "usd" => [0.12]}}],
         30_000, :infinity},
        {MockUCOPriceProvider2, __MODULE__, :fetch, [{:ok, %{"eur" => [0.30], "usd" => [0.12]}}],
         30_000, :infinity},
        {MockUCOPriceProvider3, __MODULE__, :fetch, [{:ok, %{"eur" => [0.40], "usd" => [0.12]}}],
         30_000, :infinity},
        {MockUCOPriceProvider3, __MODULE__, :fetch, [{:ok, %{"eur" => [0.50], "usd" => [0.12]}}],
         30_000, :infinity}
      ])

    assert false == UCOPrice.verify?(%{"eur" => 0.35, "usd" => 0.12})
  end

  test "verify?/1 should return false when no data are returned from all providers" do
    _ =
      HydratingCache.start_link(:uco_service, [
        {MockUCOPriceProvider1, __MODULE__, :fetch, [{:ok, %{"eur" => [], "usd" => []}}], 30_000,
         :infinity},
        {MockUCOPriceProvider2, __MODULE__, :fetch, [{:ok, %{"eur" => [], "usd" => []}}], 30_000,
         :infinity},
        {MockUCOPriceProvider3, __MODULE__, :fetch, [{:ok, %{"eur" => [], "usd" => []}}], 30_000,
         :infinity},
        {MockUCOPriceProvider3, __MODULE__, :fetch, [{:ok, %{"eur" => [], "usd" => []}}], 30_000,
         :infinity}
      ])

    assert false == UCOPrice.verify?(%{})
  end

  test "should report values even if a provider returns an error" do
    HydratingCache.start_link(:uco_service, [
      {MockUCOPriceProvider1, __MODULE__, :fetch, [{:ok, %{"eur" => [0.50], "usd" => [0.12]}}],
       30_000, :infinity},
      {MockUCOPriceProvider2, __MODULE__, :fetch, [{:error, :error_message}], 30_000, :infinity},
      {MockUCOPriceProvider3, __MODULE__, :fetch, [{:ok, %{"eur" => [0.60], "usd" => [0.12]}}],
       30_000, :infinity}
    ])

    assert {:ok, %{"eur" => 0.55, "usd" => 0.12}} = UCOPrice.fetch()
  end

  test "should handle a service timing out" do
    HydratingCache.start_link(:uco_service, [
      {MockUCOPriceProvider1, __MODULE__, :fetch, [{:ok, %{"eur" => [0.50], "usd" => [0.10]}}],
       30_000, :infinity},
      {MockUCOPriceProvider2, __MODULE__, :fetch, [:timer.sleep(5_000)], 30_000, :infinity},
      {MockUCOPriceProvider3, __MODULE__, :fetch, [{:ok, %{"eur" => [0.50], "usd" => [0.10]}}],
       30_000, :infinity}
    ])

    assert true == UCOPrice.verify?(%{"eur" => 0.50, "usd" => 0.10})
  end

  def fetch(values) do
    values
  end
end
