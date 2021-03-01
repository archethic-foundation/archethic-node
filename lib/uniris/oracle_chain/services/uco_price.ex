defmodule Uniris.OracleChain.Services.UCOPrice do
  @moduledoc """
  Define Oracle behaviors to support UCO Price feed oracle
  """

  require Logger

  alias Uniris.OracleChain.Services.Impl

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

  defp provider do
    Application.get_env(:uniris, __MODULE__) |> Keyword.fetch!(:provider)
  end
end
