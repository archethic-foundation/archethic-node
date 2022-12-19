defmodule Archethic.OracleChain.Services.UCOPrice do
  @moduledoc """
  Define Oracle behaviors to support UCO Price feed oracle
  """

  require Logger

  alias Archethic.OracleChain.Services.Impl

  @behaviour Impl

  @pairs ["usd", "eur"]

  @impl Impl
  @spec fetch() :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  def fetch do
    ## retrieve prices from configured providers and filter results marked as errors
    prices =
      providers()
      |> Task.async_stream(
        fn provider ->
          case provider.fetch(@pairs) do
            {:ok, _prices} = result ->
              result

            {:error, reason} ->
              Logger.warning("Service : #{inspect(__MODULE__)} : Cannot fetch values from
                provider: #{inspect(provider)} with reason : #{inspect(reason)}.")

              {false, provider}
          end
        end,
        on_timeout: :kill_task
      )
      |> Stream.filter(fn
        {:ok, {:ok, _result}} ->
          true

        other ->
          Logger.warning(
            "Service : #{inspect(__MODULE__)} : Unexpected answer while querying provider : #{inspect(other)}"
          )

          false
      end)
      |> Enum.map(fn
        {_, {_, result = %{}}} ->
          result

        other_service_answer_format ->
          Logger.error(
            "Service : #{inspect(__MODULE__)} : Unexpected answer while querying provider : #{inspect(other_service_answer_format)}, ignoring."
          )

          %{}
      end)

      ## split prices in a list per currency. If a service returned a list of prices of a currency,
      ## they will be medianed first before being added to list
      |> split_prices()
      ## compute median per currency list
      |> median_prices()

    {:ok, prices}
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

  defp median_prices(map_prices = %{}) do
    Enum.reduce(map_prices, %{}, fn {currency, values}, acc ->
      Map.put(acc, currency, median(values))
    end)
  end

  ## To avoid all calculation from general clause to follow
  defp median([price]) do
    price
  end

  defp median(prices) do
    sorted = Enum.sort(prices)
    length_list = Enum.count(sorted)

    case rem(length_list, 2) do
      1 -> Enum.at(sorted, div(length_list, 2) + 1)
      ## If we have an even number, media is the average of the two medium nu,bers
      0 -> Enum.slice(sorted, div(length_list, 2), 2) |> Enum.sum() |> Kernel./(2)
    end
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

  defp split_prices(list_of_maps_of_prices) do
    split_prices(list_of_maps_of_prices, %{})
  end

  defp split_prices([], acc) do
    acc
  end

  defp split_prices(
         [%{} = prices | other_prices],
         aggregated_data
       ) do
    new_aggregated_data =
      Enum.reduce(prices, aggregated_data, fn
        ## Assert we have at least one value for the currency
        {currency, [_ | _] = values}, acc ->
          Map.update(acc, String.downcase(currency), [median(values)], fn previous_values ->
            previous_values ++ [median(values)]
          end)

        other, acc ->
          Logger.warning(
            "No or Unexpected value : #{inspect(other)} while aggregating service result"
          )

          acc
      end)

    split_prices(other_prices, new_aggregated_data)
  end
end
