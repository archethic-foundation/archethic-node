defmodule Uniris.Oracles.UcoPrice do
  alias Uniris.Oracles.Coingecko

  @oracles [Coingecko, Coingecko]

  # Public

  @spec start() :: [Keyword.t()]
  def start do
    @oracles
    |> Task.async_stream(fn m -> m.start() end)
    |> Enum.to_list()
  end

  @spec fetch({:date, DateTime.t()}) :: list(map())
  def fetch({:date, date}) do
    @oracles
    |> Task.async_stream(fn m -> m.fetch(date) end)
    |> Enum.to_list()
    |> Enum.filter(fn response -> elem(response, 0) == :ok end)
    |> Enum.map(fn response -> elem(response, 1) end)
  end
end
