defmodule Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika do
  @moduledoc false

  alias Archethic.OracleChain.Services.UCOPrice.Providers.Impl

  @behaviour Impl

  require Logger

  @impl Impl
  @spec fetch(list(binary())) :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  def fetch(pairs) when is_list(pairs) do
    pairs_str = Enum.join(pairs, ",")

    httpc_options = [
      ssl: [
        verify: :verify_peer,
        cacertfile: CAStore.file_path(),
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ],
      connect_timeout: 1000,
      timeout: 2000
    ]

    query =
      String.to_charlist(
        "https://api.coinpaprika.com/v1/coins/uco-uniris/markets?quotes=#{pairs_str}"
      )

    with {:ok, {{_, 200, 'OK'}, _headers, body}} <-
           :httpc.request(:get, {query, []}, httpc_options, []),
         {:ok, payload} <- Jason.decode(body) do
      quotes =
        payload
        |> Enum.map(fn %{"quotes" => quotes} -> quotes end)

      prices =
        pairs
        |> Enum.map(fn pair ->
          {
            pair,
            quotes
            |> Enum.map(
              &(&1
                |> get_in([String.downcase(pair), "price"])
                |> Enum.reject(fn price -> is_nil(price) end))
            )
          }
        end)
        |> Enum.reject(fn {_pair, prices} -> prices == [] end)
        |> Enum.into(%{})

      {:ok, prices}
    else
      {:ok, {{_, _, status}, _, _}} ->
        {:error, status}

      {:error, %Jason.DecodeError{}} ->
        {:error, "invalid content"}

      :error ->
        {:error, "invalid content"}

      {:error, _} = e ->
        e
    end
  end
end
