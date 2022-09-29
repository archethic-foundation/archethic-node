defmodule Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko do
  @moduledoc false

  alias Archethic.OracleChain.Services.UCOPrice.Providers.Impl

  @behaviour Impl

  require Logger

  @impl Impl
  @spec fetch(list(binary())) :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  def fetch(pairs) when is_list(pairs) do
    pairs_str = Enum.join(pairs, ",")

    query =
      String.to_charlist(
        "https://api.coingecko.com/api/v3/simple/price?ids=archethic&vs_currencies=#{pairs_str}"
      )

    httpc_options = [
      ssl: [
        verify: :verify_peer,
        cacertfile: CAStore.file_path(),
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    with {:ok, {{_, 200, 'OK'}, _headers, body}} <-
           :httpc.request(:get, {query, []}, httpc_options, []),
         {:ok, payload} <- Jason.decode(body),
         {:ok, prices} <- Map.fetch(payload, "archethic") do
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
