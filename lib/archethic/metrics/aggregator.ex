defmodule ArchEthic.Metrics.Aggregator do
  @moduledoc """
  Provide aggregation methods for the metrics collected
  """

  @doc """
  Add the TPS based on the transaction validation durations

  ## Examples

      iex> [
      ...>   %{ "archethic_mining_full_transaction_validation_duration" => %{count: 10, sum: 1.5}},
      ...>   %{ "archethic_mining_full_transaction_validation_duration" => %{count: 10, sum: 1.5 }},
      ...>   %{ "archethic_mining_full_transaction_validation_duration" => %{count: 10, sum: 1.5 }},
      ...> ] |> Aggregator.inject_tps()
      [
        %{ "tps" => 6.666666666666667 },
        %{ "archethic_mining_full_transaction_validation_duration" => %{count: 10, sum: 1.5}},
        %{ "archethic_mining_full_transaction_validation_duration" => %{count: 10, sum: 1.5}},
        %{ "archethic_mining_full_transaction_validation_duration" => %{count: 10, sum: 1.5}}
      ]
  """
  def inject_tps(metrics) do
    %{count: count, sum: sum} =
      Enum.reduce(metrics, %{count: 0, sum: 0.0}, fn
        %{
          "archethic_mining_full_transaction_validation_duration" => %{count: count, sum: sum}
        },
        acc ->
          acc
          |> Map.update!(:count, &(&1 + count))
          |> Map.update!(:sum, &(&1 + sum))

        _, acc ->
          acc
      end)

    if count > 0.0 do
      tps = count / sum
      [%{"tps" => tps} | metrics]
    else
      metrics
    end
  end

  @doc """
  Reduce through aggregation metrics values

  ## Examples
      iex> [
      ...>   %{"archethic_p2p_send_message_duration" => %{count: 100, sum: 10}},
      ...>   %{"archethic_p2p_send_message_duration" => %{count: 200, sum: 20}},
      ...>   %{"archethic_p2p_send_message_duration" => %{count: 300, sum: 30}}
      ...> ]|> Aggregator.reduce_values()
      %{
        "archethic_p2p_send_message_duration" => %{count: 600, sum: 60}
      }
  """
  def reduce_values(list_of_metrics) do
    list_of_metrics
    |> Enum.map(&Map.to_list/1)
    |> Enum.reduce(%{}, fn
      [{"tps", tps}], acc ->
        Map.put(acc, "tps", tps)

      [{metric_name, %{count: count, sum: sum}}], acc ->
        update_histogram_acc(metric_name, count, sum, acc)

      [{metric_name, value}], acc ->
        update_guage_acc(metric_name, value, acc)
    end)
  end

  defp update_histogram_acc(metric_name, count, sum, acc) do
    acc
    |> update_in([Access.key(metric_name, %{}), Access.key(:sum, 0)], &(&1 + sum))
    |> update_in([Access.key(metric_name, %{}), Access.key(:count, 0)], &(&1 + count))
  end

  defp update_guage_acc(metric_name, value, acc) do
    update_in(acc, [Access.key(metric_name, 0)], &(&1 + value))
  end

  @doc """
  Aggregate and summarize the metrics

  For histograms, it produces an average of the values by doing: `sum/count`

  ## Examples

      iex> %{
      ...>   "archethic_mining_full_transaction_validation_duration" => %{count: 5, sum: 10},
      ...>   "archethic_p2p_send_message_duration" => %{count: 600, sum: 60},
      ...>   "tps" => 10.0,
      ...>   "vm_memory_atom" => 600.0
      ...> }|> Aggregator.summarize()
      [
         %{"archethic_mining_full_transaction_validation_duration" => 2.0},
         %{"archethic_p2p_send_message_duration" => 0.1},
         %{"tps" => 10.0},
         %{"vm_memory_atom" => 600.0}
      ]
  """
  @spec summarize(%{
          String.t() => number(),
          String.t() => %{count: number(), sum: number()}
        }) :: [%{String.t() => number()}, ...]
  def summarize(map_of_metrics) do
    Enum.map(map_of_metrics, fn {metric_name, metric_value} ->
      case metric_value do
        %{count: 0, sum: _sum} -> %{metric_name => 0.0}
        %{count: count, sum: sum} -> %{metric_name => sum / count}
        value -> %{metric_name => value}
      end
    end)
  end
end
