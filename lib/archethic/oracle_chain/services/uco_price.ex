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
    prices =
      Enum.map(providers(), fn provider ->
        provider.fetch(@pairs)
      end)
      |> Enum.filter(fn
        {:ok, _} -> true
        {:error, _} -> false
      end)
      |> split_prices()
      |> median_prices()

    {:ok, prices}
  end

  @impl Impl
  @spec verify?(%{required(String.t()) => any()}) :: boolean
  def verify?(prices_prior = %{}) do
    case fetch() do
      {:ok, prices_now} ->
        Enum.all?(@pairs, fn pair ->
          compare_price(Map.fetch!(prices_prior, pair), Map.fetch!(prices_now, pair))
        end)

      {:error, reason} ->
        Logger.warning("Cannot fetch UCO price - reason: #{inspect(reason)}")
        false
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

  defp median_prices({list_of_euro_prices, list_of_usd_prices}) do
    %{"eur" => median(list_of_euro_prices), "usd" => median(list_of_usd_prices)}
  end

  defp median(prices) do
    sorted = Enum.sort(prices)
    length_list = Enum.count(sorted)

    case rem(length_list, 2) do
      1 -> Enum.at(sorted, div(length_list, 2) + 1)
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

  defp split_prices(list_of_map_of_prices) do
    split_prices(list_of_map_of_prices, {[], []})
  end

  defp split_prices([], acc) do
    acc
  end

  defp split_prices(
         [%{"eur" => euro_price, "usd" => usd_price} | other_prices],
         {euro_prices, usd_prices}
       ) do
    split_prices(other_prices, {euro_prices ++ [euro_price], usd_prices ++ [usd_price]})
  end
end
