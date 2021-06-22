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
          # TODO: use a deviation comparison function
          abs(Map.fetch!(prices_prior, pair) / Map.fetch!(prices_now, pair)) == 1.0
        end)

      _ ->
        false
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

  defp provider do
    Application.get_env(:archethic, __MODULE__) |> Keyword.fetch!(:provider)
  end
end
