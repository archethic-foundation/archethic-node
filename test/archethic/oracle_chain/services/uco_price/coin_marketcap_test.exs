defmodule Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCapTest do
  use ExUnit.Case

  alias Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCapUniris
  alias Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCapArchethic

  @tag oracle_provider: true
  test "fetch/1 should get the current UCO price from CoinMarketCap (uniris)" do
    assert {:ok, %{"eur" => prices}} = CoinMarketCapUniris.fetch(["eur"])
    assert is_list(prices)
  end

  @tag oracle_provider: true
  test "fetch/1 should get the current UCO price from CoinMarketCap (archethic)" do
    assert {:ok, %{"eur" => prices}} = CoinMarketCapArchethic.fetch(["eur"])
    assert is_list(prices)
  end
end
