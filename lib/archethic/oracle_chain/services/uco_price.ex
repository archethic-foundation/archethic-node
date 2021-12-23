defmodule ArchEthic.OracleChain.Services.UCOPrice do
  @moduledoc """
  Define Oracle behaviors to support UCO Price feed oracle
  """

  require Logger

  alias ArchEthic.OracleChain.Services.Impl

  @behaviour Impl

  @pairs ["usd", "eur"]

  @impl Impl
  @spec fetch() :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  def fetch, do: provider().fetch(@pairs)

  @impl Impl
  @spec verify?(%{required(String.t()) => any()}) :: boolean
  def verify?(prices_prior = %{}) do
    case provider().fetch(@pairs) do
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

  defp provider do
    Application.get_env(:archethic, __MODULE__) |> Keyword.fetch!(:provider)
  end
end
