defmodule Archethic.Metrics.Collector do
  @moduledoc """
  Handle the flow of metrics collection
  """

  alias Archethic.Metrics.Parser

  @callback fetch_metrics(:inet.ip_address(), :inet.port_number()) ::
              {:ok, String.t()} | {:error, any()}

  @doc """
  Fetch metrics from the endpoint
  """
  @spec fetch_metrics(:inet.ip_address(), port()) :: {:ok, map()}
  def fetch_metrics(ip, port) do
    with {:ok, metrics} <- service().fetch_metrics(ip, port) do
      structured_metrics =
        metrics
        |> Parser.extract_from_string()
        |> Parser.reduce_metrics()

      {:ok, structured_metrics}
    end
  end

  defp service do
    Application.get_env(
      :archethic,
      __MODULE__,
      __MODULE__.MetricsEndpoint
    )
  end
end
