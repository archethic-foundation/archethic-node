defmodule Archethic.OracleChain.Services.UCOPrice do
  @moduledoc """
  Define Oracle behaviors to support UCO Price feed oracle
  """

  require Logger

  alias Archethic.OracleChain.Services.Impl
  alias Archethic.Utils

  alias Archethic.Utils.HydratingCache

  @behaviour Impl

  @precision_digits 5

  @pairs ["usd", "eur"]

  @impl Impl
  @spec fetch() :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  def fetch do
    ## Start a supervisor for the feching tasks
    {:ok, fetching_tasks_supervisor} = Task.Supervisor.start_link()
    ## retrieve prices from configured providers and filter results marked as errors
    prices =
      Enum.map(providers(), fn provider ->
        case HydratingCache.get(
               :"Elixir.Archethic.Utils.HydratingCache.uco_service",
               provider,
               3000
             ) do
          {:error, reason} ->
            Logger.warning(
              "Service UCOPrice cannot fetch values from provider: #{inspect(provider)} with reason : #{inspect(reason)}."
            )

            []

          {:ok, result} ->
            {provider, result}
        end
      end)
      |> List.flatten()
      |> Enum.filter(fn
        {_, %{}} ->
          true

        other ->
          Logger.error("Service UCOPrice cannot fetch values from provider: #{inspect(other)}.")
          false
      end)
      |> Enum.map(fn
        {_, result = %{}} ->
          result
      end)
      ## Here stream looks like : [%{"eur"=>[0.44], "usd"=[0.32]}, ..., %{"eur"=>[0.42, 0.43], "usd"=[0.35]}]
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

    Supervisor.stop(fetching_tasks_supervisor, :normal, 3_000)
    {:ok, prices}
  end

  @spec agregate_providers_data(map(), map()) :: map()
  defp agregate_providers_data(provider_results, acc) do
    provider_results
    |> Enum.reduce(acc, fn
      {currency, values}, acc when values != [] ->
        Map.update(acc, String.downcase(currency), values, fn
          previous_values ->
            previous_values ++ values
        end)

      {_currency, _values}, acc ->
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
          compare_price(Map.fetch!(prices_prior, pair), Map.fetch!(prices_now, pair))
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

  defp providers do
    Application.get_env(:archethic, __MODULE__) |> Keyword.fetch!(:providers)
  end
end
