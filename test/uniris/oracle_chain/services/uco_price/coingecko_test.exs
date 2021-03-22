defmodule Uniris.OracleChain.Services.UCOPrice.Providers.CoingeckoTest do
  use ExUnit.Case

  alias Uniris.OracleChain.Services.UCOPrice.Providers.Coingecko

  @tag oracle_provider: true
  test "fetch/1 should get the current UCO price from CoinGecko" do
    assert {:ok, %{"eur" => _}} = Coingecko.fetch(["eur"])
  end
end
