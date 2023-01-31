defmodule Archethic.OracleChain.Services.UCOPriceTest do
  use ExUnit.Case

  alias Archethic.OracleChain.Services.UCOPrice

  import Mox

  test "fetch/0 should retrieve some data and build a map with the oracle name in it" do
    MockUCOPriceProvider1
    |> expect(:fetch, fn pairs ->
      res =
        Enum.map(pairs, fn pair ->
          {pair, [:rand.uniform_real()]}
        end)
        |> Enum.into(%{})

      {:ok, res}
    end)

    MockUCOPriceProvider2
    |> expect(:fetch, fn pairs ->
      res =
        Enum.map(pairs, fn pair ->
          {pair, [:rand.uniform_real()]}
        end)
        |> Enum.into(%{})

      {:ok, res}
    end)

    MockUCOPriceProvider3
    |> expect(:fetch, fn pairs ->
      res =
        Enum.map(pairs, fn pair ->
          {pair, [:rand.uniform_real()]}
        end)
        |> Enum.into(%{})

      {:ok, res}
    end)

    assert {:ok, %{"eur" => _, "usd" => _}} = UCOPrice.fetch()
  end

  test "fetch/0 should retrieve some data and build a map with the oracle name in it and keep the precision to 5" do
    MockUCOPriceProvider1
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.123456789], "usd" => [0.123454789]}}
    end)

    MockUCOPriceProvider2
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.123456789], "usd" => [0.123454789]}}
    end)

    MockUCOPriceProvider3
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.123456789], "usd" => [0.123454789]}}
    end)

    assert {:ok, %{"eur" => 0.12346, "usd" => 0.12345}} = UCOPrice.fetch()
  end

  describe "verify/1" do
    test "should return true if the prices are the good one" do
      MockUCOPriceProvider1
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => [0.20], "usd" => [0.11]}}
      end)

      MockUCOPriceProvider2
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => [0.30, 0.40], "usd" => [0.12, 0.13]}}
      end)

      MockUCOPriceProvider3
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => [0.50], "usd" => [0.14]}}
      end)

      assert {:ok, %{"eur" => 0.35, "usd" => 0.125}} == UCOPrice.fetch()
    end

    test "should return false if the prices have deviated" do
      MockUCOPriceProvider1
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => [0.20], "usd" => [0.12]}}
      end)

      MockUCOPriceProvider2
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => [0.20], "usd" => [0.12]}}
      end)

      MockUCOPriceProvider3
      |> expect(:fetch, fn _pairs ->
        {:ok, %{"eur" => [0.20], "usd" => [0.12]}}
      end)

      assert false == UCOPrice.verify?(%{"eur" => 0.10, "usd" => 0.14})
    end
  end

  test "should return the median value when multiple providers queried" do
    MockUCOPriceProvider1
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.20], "usd" => [0.12]}}
    end)

    MockUCOPriceProvider2
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.30], "usd" => [0.12]}}
    end)

    MockUCOPriceProvider3
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.40], "usd" => [0.12]}}
    end)

    assert true == UCOPrice.verify?(%{"eur" => 0.30, "usd" => 0.12})
  end

  test "should return the average of median values when a even number of providers queried" do
    ## Define a fourth mock to have even number of mocks
    Mox.defmock(MockUCOPriceProvider4,
      for: Archethic.OracleChain.Services.UCOPrice.Providers.Impl
    )

    ## Backup old environment variable, and update it with fourth provider
    old_env = Application.get_env(:archethic, Archethic.OracleChain.Services.UCOPrice)

    new_uco_env =
      old_env
      |> Keyword.replace(:providers, [
        MockUCOPriceProvider1,
        MockUCOPriceProvider2,
        MockUCOPriceProvider3,
        MockUCOPriceProvider4
      ])

    Application.put_env(:archethic, Archethic.OracleChain.Services.UCOPrice, new_uco_env)

    ## Define mocks expectations
    MockUCOPriceProvider1
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.20], "usd" => [0.12]}}
    end)

    MockUCOPriceProvider2
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.30], "usd" => [0.12]}}
    end)

    MockUCOPriceProvider3
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.40], "usd" => [0.12]}}
    end)

    MockUCOPriceProvider4
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.50], "usd" => [0.12]}}
    end)

    ## Restore original environment
    Application.put_env(:archethic, Archethic.OracleChain.Services.UCOPrice, old_env)

    assert false == UCOPrice.verify?(%{"eur" => 0.35, "usd" => 0.12})
  end

  test "verify?/1 should return false when no data are returned from all providers" do
    MockUCOPriceProvider1
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [], "usd" => []}}
    end)

    MockUCOPriceProvider2
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [], "usd" => []}}
    end)

    MockUCOPriceProvider3
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [], "usd" => []}}
    end)

    assert false == UCOPrice.verify?(%{})
  end

  test "should report values even if a provider returns an error" do
    MockUCOPriceProvider1
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.50], "usd" => [0.12]}}
    end)

    MockUCOPriceProvider2
    |> expect(:fetch, fn _pairs ->
      {:error, :error_message}
    end)

    MockUCOPriceProvider3
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.60], "usd" => [0.12]}}
    end)

    assert {:ok, %{"eur" => 0.55, "usd" => 0.12}} = UCOPrice.fetch()
  end

  test "should handle a service timing out" do
    MockUCOPriceProvider1
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.50], "usd" => [0.10]}}
    end)

    MockUCOPriceProvider2
    |> expect(:fetch, fn _pairs ->
      :timer.sleep(5_000)
    end)

    MockUCOPriceProvider3
    |> expect(:fetch, fn _pairs ->
      {:ok, %{"eur" => [0.50], "usd" => [0.10]}}
    end)

    assert true == UCOPrice.verify?(%{"eur" => 0.50, "usd" => 0.10})
  end
end
