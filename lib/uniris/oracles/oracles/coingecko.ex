defmodule Uniris.Oracles.Coingecko do
  @moduledoc false

  use HTTPoison.Base

  @endpoint "https://api.coingecko.com/api/v3/coins/uniris/history?date="

  # Public

  @spec fetch(DateTime.t()) :: map()
  def fetch(date) do
    "#{date.day}-#{date.month}-#{date.year}"
    |> get!
    |> Map.fetch!(:body)
  end

  # HTTPoison.Base

  @impl HTTPoison.Base
  def process_request_url(date), do: @endpoint <> date

  @impl HTTPoison.Base
  def process_response_body(body) do
    Jason.decode!(body)
    |> Map.fetch!("market_data")
    |> Map.fetch!("current_price")
    |> Jason.encode!()
  end
end
