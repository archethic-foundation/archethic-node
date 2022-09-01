defmodule Archethic.Metrics.Aggregator do
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
      ...> ] |> Aggregator.inject_transaction_counter()
      [
        %{ "nb_transactions" => 10 },
        %{ "archethic_mining_full_transaction_validation_duration" => %{count: 10, sum: 1.5}},
        %{ "archethic_mining_full_transaction_validation_duration" => %{count: 10, sum: 1.5}},
        %{ "archethic_mining_full_transaction_validation_duration" => %{count: 10, sum: 1.5}}
      ]
  """
  @spec inject_transaction_counter(list(map())) :: list(map())
  def inject_transaction_counter(metrics) do
    transaction_validation_metrics =
      Enum.filter(metrics, fn
        %{"archethic_mining_full_transaction_validation_duration" => _} -> true
        _ -> false
      end)

    count =
      transaction_validation_metrics
      |> Enum.map(fn %{"archethic_mining_full_transaction_validation_duration" => %{count: count}} ->
        count
      end)
      |> Enum.sum()

    if count > 0 do
      [%{"nb_transactions" => div(count, length(transaction_validation_metrics))} | metrics]
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
  @spec reduce_values(list(map())) :: map()
  def reduce_values(list_of_metrics) do
    list_of_metrics
    |> Enum.map(&Map.to_list/1)
    |> Enum.reduce(%{}, fn
      [{"nb_transactions", tps}], acc ->
        Map.put(acc, "nb_transactions", tps)

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
      ...>   "nb_transactions" => 10.0,
      ...>   "vm_memory_atom" => 600.0
      ...> }|> Aggregator.summarize()
      [
         %{"archethic_mining_full_transaction_validation_duration" => 2.0},
         %{"archethic_p2p_send_message_duration" => 0.1},
         %{"nb_transactions" => 10.0},
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
        %{count: 0, sum: _sum} -> %{metric_name => 0}
        %{count: count, sum: sum} -> %{metric_name => sum / count}
        value -> %{metric_name => value}
      end
    end)
  end
end
