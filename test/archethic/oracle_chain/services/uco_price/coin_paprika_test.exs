defmodule Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprikaTest do
  use ExUnit.Case

  alias Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika

  @tag oracle_provider: true
  test "fetch/1 should get the current UCO price from CoinGecko" do
    assert {:ok, %{"eur" => prices}} = CoinPaprika.fetch(["eur"])
    assert is_list(prices)
  end
end
