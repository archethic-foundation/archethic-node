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
      |> get_mode()

    if count > 0 do
      [%{"nb_transactions" => count} | metrics]
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
        "archethic_p2p_send_message_duration" => %{ sum: [30, 20, 10]}
      }
  """
  @spec reduce_values(list(map())) :: map()
  def reduce_values(list_of_metrics) do
    list_of_metrics
    |> Enum.map(&Map.to_list/1)
    |> Enum.reduce(%{}, fn
      [{"nb_transactions", nb_transactions}], acc ->
        Map.put(acc, "nb_transactions", nb_transactions)

      [{metric_name, %{count: _count, sum: sum}}], acc ->
        update_in(acc, [Access.key(metric_name, %{}), Access.key(:sum, [])], &[sum | &1])

      # update_histogram_acc(metric_name, count, sum, acc)

      [{metric_name, value}], acc ->
        update_guage_acc(metric_name, value, acc)
    end)
  end

  # defp update_histogram_acc(metric_name, count, sum, acc) do
  #  acc
  #  |> update_in([Access.key(metric_name, %{}), Access.key(:sum, 0)], &(&1 + sum))
  #  |> update_in([Access.key(metric_name, %{}), Access.key(:count, 0)], &(&1 + count))
  # end

  defp update_guage_acc(metric_name, value, acc) do
    update_in(acc, [Access.key(metric_name, 0)], &(&1 + value))
  end

  @doc """
  Aggregate and summarize the metrics

  For histograms, it produces an average of the values by doing: `sum/count`

  ## Examples

      iex> %{
      ...>   "archethic_mining_full_transaction_validation_duration" => %{ sum: [100, 50, 80, 100, 200, 110, 90, 100] },
      ...>   "archethic_p2p_send_message_duration" => %{ sum: [90, 10, 30, 40, 50, 70, 30] },
      ...>   "nb_transactions" => 10.0,
      ...>   "vm_memory_atom" => 600.0
      ...> }|> Aggregator.summarize()
      [
         %{"archethic_mining_full_transaction_validation_duration" => 100},
         %{"archethic_p2p_send_message_duration" => 30},
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
        %{sum: sum} ->
          %{metric_name => get_mode(sum)}

        value ->
          %{metric_name => value}
      end
    end)
  end

  defp get_mode(list) do
    frequencies =
      list
      # Get the mode of the series
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_, frequencies} -> frequencies end, :desc)

    mode =
      frequencies
      |> Enum.at(0, {0, 0})
      |> elem(0)

    if Enum.map(frequencies, fn {_, f} -> f end) |> Enum.uniq() |> length() == 1 do
      # When we have the same frequencies we take the highest value
      frequencies
      |> Enum.max(fn -> {0, 0} end)
      |> elem(0)
    else
      mode
    end
  end
end
