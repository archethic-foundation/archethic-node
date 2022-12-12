defmodule Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCap do
  @moduledoc false

  alias Archethic.OracleChain.Services.UCOPrice.Providers.Impl

  @behaviour Impl

  require Logger

  @impl Impl
  @spec fetch(list(binary())) :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  def fetch(pairs) when is_list(pairs) do
    query = 'http://coinmarketcap.com/currencies/uniris/markets/'

    httpc_options = [
      connect_timeout: 1000,
      timeout: 2000
    ]

    Enum.map(pairs, fn pair ->
      headers = [
        {'user-agent',
         'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.169 Safari/537.36'},
        {'accept', 'text/html'},
        {'accept-language', 'en-US,en;q=0.9,es;q=0.8'},
        {'upgrade-insecure-requests', '1'},
        {'referer', 'https://archethic.net/'},
        {'Cookie', 'currency=#{pair}'}
      ]

      {:ok, {{_, 200, 'OK'}, _headers, body}} =
        :httpc.request(:get, {query, headers}, httpc_options, [])

      {:ok, document} = Floki.parse_document(body)

      price =
        Floki.find(document, "div.priceTitle > div.priceValue > span")
        |> Floki.text()
        |> String.graphemes()
        |> Enum.filter(&(&1 in [".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]))
        |> Enum.into("")

      {pair, price}
    end)
    |> Enum.into(%{})
  end
end
