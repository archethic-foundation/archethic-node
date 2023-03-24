defmodule Archethic.OracleChain.Services.UCOPrice do
  @moduledoc """
  Define Oracle behaviors to support UCO Price feed oracle
  """

  require Logger

  alias Archethic.OracleChain.Services.Impl
  alias Archethic.OracleChain.Services.ProviderCacheSupervisor

  alias Archethic.Utils

  @behaviour Impl

  @precision_digits 5

  @pairs ["usd", "eur"]

  @impl Impl
  def cache_child_spec do
    Supervisor.child_spec({ProviderCacheSupervisor, providers: providers(), fetch_args: @pairs},
      id: CacheSupervisor
    )
  end

  defp providers do
    Application.get_env(:archethic, __MODULE__) |> Keyword.fetch!(:providers)
  end

  @impl Impl
  @spec fetch() :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  def fetch do
    # retrieve prices from configured providers and filter results marked as errors
    # Here stream looks like : [%{"eur"=>[0.44], "usd"=[0.32]}, ..., %{"eur"=>[0.42, 0.43], "usd"=[0.35]}]
    prices =
      providers()
      |> ProviderCacheSupervisor.get_values()
      |> Enum.reduce(%{}, &agregate_providers_data/2)
      |> Enum.reduce(%{}, fn {currency, values}, acc ->
        price =
          values
          |> Utils.median()
          |> Archethic.Cldr.Number.to_string!(
            currency: currency,
            currency_symbol: "",
            fractional_digits: @precision_digits
          )
          |> String.to_float()

        Map.put(acc, currency, price)
      end)

    {:ok, prices}
  end

  defp agregate_providers_data(provider_results, acc) do
    provider_results
    |> Enum.reduce(acc, fn
      {currency, values}, acc when values != [] ->
        Map.update(acc, String.downcase(currency), values, fn
          previous_values ->
            previous_values ++ values
        end)

      _, acc ->
        acc
    end)
  end

  @impl Impl
  @spec verify?(%{required(String.t()) => any()}) :: boolean
  def verify?(prices_prior = %{}) do
    case fetch() do
      {:ok, prices_now} when prices_now == %{} ->
        Logger.error("Cannot fetch UCO price - reason: no data from any service.")
        false

      {:ok, prices_now} ->
        Enum.all?(@pairs, fn pair ->
          compare_price(
            Map.fetch!(prices_prior, pair),
            Map.get(prices_now, pair, Map.get(prices_prior, pair, 0.0))
          )
        end)
    end
  end

  defp compare_price(price_prior, price_now) do
    deviation_threshold = 0.01

    deviation =
      [price_prior, price_now]
      |> standard_deviation()
      |> Float.round(3)

    if deviation < deviation_threshold do
      true
    else
      Logger.warning(
        "UCO price deviated from #{deviation} % - previous price: #{price_prior} - new price: #{price_now} "
      )

      false
    end
  end

  defp standard_deviation(prices) do
    prices_mean = mean(prices)
    variance = prices |> Enum.map(fn x -> (prices_mean - x) * (prices_mean - x) end) |> mean()
    :math.sqrt(variance)
  end

  defp mean(prices, t \\ 0, l \\ 0)
  defp mean([], t, l), do: t / l

  defp mean([x | xs], t, l) do
    mean(xs, t + x, l + 1)
  end

  @impl Impl
  @spec parse_data(map()) :: {:ok, map()} | :error
  def parse_data(service_data) when is_map(service_data) do
    valid? =
      Enum.all?(service_data, fn
        {key, val} when key in @pairs and is_float(val) ->
          true

        _ ->
          false
      end)

    if valid?, do: {:ok, service_data}, else: :error
  end

  def parse_data(_), do: {:error, :invalid_data}
end
