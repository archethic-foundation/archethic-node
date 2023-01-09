defmodule Archethic.Metrics.Parser do
  @moduledoc """
  Parses metrics data and convert into structured data
  """

  @typep metric_data :: %{
           labels: %{String.t() => number()} | nil,
           quantiles: %{String.t() => number()} | nil,
           count: number() | nil,
           sum: number() | nil,
           value: number() | nil
         }

  @type metric :: %{
          metrics: list(metric_data()),
          name: String.t(),
          type: String.t()
        }

  @doc """
  Convert multi-line metrics data into structured data

  ## Examples

     iex> \"""
     ...> # HELP archethic_contract_parsing_duration
     ...> # TYPE archethic_contract_parsing_duration histogram
     ...> archethic_contract_parsing_duration_bucket{le="0.001"} 153
     ...> archethic_contract_parsing_duration_bucket{le="+Inf"} 177
     ...> archethic_contract_parsing_duration_sum 0.12
     ...> archethic_contract_parsing_duration_count 177
     ...> # HELP vm_memory_atom
     ...> # TYPE vm_memory_atom gauge
     ...> vm_memory_atom 1589609
     ...> # HELP archethic_election_storage_nodes_duration
     ...> # TYPE archethic_election_storage_nodes_duration histogram
     ...> archethic_election_storage_nodes_duration_bucket{nb_nodes="1",le="0.001"} 1329
     ...> archethic_election_storage_nodes_duration_bucket{nb_nodes="1",le="+Inf"} 1336
     ...> archethic_election_storage_nodes_duration_sum{nb_nodes="1"} 0.073
     ...> archethic_election_storage_nodes_duration_count{nb_nodes="1"} 1336
     ...> archethic_election_storage_nodes_duration_bucket{nb_nodes="3",le="0.001"} 21997
     ...> archethic_election_storage_nodes_duration_bucket{nb_nodes="3",le="+Inf"} 22437
     ...> archethic_election_storage_nodes_duration_sum{nb_nodes="3"} 5.7
     ...> archethic_election_storage_nodes_duration_count{nb_nodes="3"} 22437
     ...> archethic_election_storage_nodes_duration_bucket{nb_nodes="2",le="0.001"} 121
     ...> archethic_election_storage_nodes_duration_bucket{nb_nodes="2",le="+Inf"} 128
     ...> archethic_election_storage_nodes_duration_sum{nb_nodes="2"} 0.02
     ...> archethic_election_storage_nodes_duration_count{nb_nodes="2"} 128
     ...> \""" |> Parser.extract_from_string()
     [
       %{
         metrics: [
           %{
             labels: %{"nb_nodes" => "\\"1\\""},
             quantiles: %{"\\"+Inf\\"" => 1336, "\\"0.001\\"" => 1329},
             count: 1336,
             sum: 0.073
           },
           %{
             labels: %{"nb_nodes" => "\\"2\\""},
             quantiles: %{"\\"+Inf\\"" => 128, "\\"0.001\\"" => 121},
             count: 128,
             sum: 0.02
           },
           %{
             labels: %{"nb_nodes" => "\\"3\\""},
             quantiles: %{"\\"+Inf\\"" => 22437, "\\"0.001\\"" => 21997},
             count: 22437,
             sum: 5.7
           }
         ],
         name: "archethic_election_storage_nodes_duration",
         type: "histogram"
       },
       %{
         metrics: [
           %{value: 1589609}
         ],
         name: "vm_memory_atom",
         type: "gauge"
       },
       %{
         metrics: [
           %{
             quantiles: %{"\\"+Inf\\"" => 177, "\\"0.001\\"" => 153},
             count: 177,
             sum: 0.12
           }
         ],
         name: "archethic_contract_parsing_duration",
         type: "histogram"
       }
     ]

  """
  @spec extract_from_string(String.t()) :: list(metric())
  def extract_from_string(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{current: %{}, metrics: []}, fn line, acc ->
      %{content: line, current: acc.current, metrics: acc.metrics}
      |> parse_help()
      |> parse_type()
      |> parse_metric()
    end)
    |> finalize()
    |> Enum.map(&normalize/1)
  end

  defp finalize(%{current: current, metrics: metrics}) do
    [current | metrics]
  end

  defp parse_help(acc = %{content: content, current: current}) do
    case Regex.run(~r/HELP (.*)/, content) do
      [_, name] ->
        case Map.get(current, :name) do
          nil ->
            Map.put(acc, :current, %{name: String.trim(name)})

          _ ->
            acc
            |> Map.update!(:metrics, &[current | &1])
            |> Map.put(:current, %{name: name |> String.trim()})
        end

      _ ->
        acc
    end
  end

  defp parse_type(acc = %{content: content, current: current}) do
    case Regex.run(~r/TYPE (.*) (.*)/, content) do
      [_, _, type] ->
        %{acc | current: Map.put(current, :type, type)}

      _ ->
        acc
    end
  end

  defp parse_metric(acc = %{content: content, current: %{name: metric_name}}) do
    case Regex.run(~r/^#{metric_name}_([[:alpha:]]*)({.*})? (.*)$/, content) do
      [_, key, labels, value] ->
        bucket_extract_update(acc, key, labels, parse_value(value))

      nil ->
        case Regex.run(~r/^#{metric_name} (.*)$/, content) do
          [_, value] ->
            put_in(acc, [:current, Access.key(:metrics, %{}), %{}], %{value: parse_value(value)})

          _ ->
            acc
        end
    end
  end

  defp parse_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {val, ""} ->
        val

      {_, _} ->
        {val, ""} = Float.parse(value)
        val
    end
  end

  defp bucket_extract_update(acc, key, labels, value) do
    %{labels: labels, quantiles: quantiles} = extract_labels(labels, value)

    update_in(
      acc,
      [:current, Access.key(:metrics, %{}), Access.key(labels, %{})],
      fn label_metric ->
        case key do
          "bucket" ->
            update_sub_metric(label_metric, key, quantiles)

          _ ->
            update_sub_metric(label_metric, key, value)
        end
      end
    )
  end

  def extract_labels(labels, value) do
    labels
    |> String.replace("{", "")
    |> String.replace("}", "")
    |> String.split(",", trim: true)
    |> Enum.reduce(%{labels: %{}, quantiles: %{}}, fn label, acc ->
      [k, v] = String.split(label, "=")

      case k do
        "le" ->
          Map.update!(acc, :quantiles, &Map.put(&1, v, value))

        _ ->
          Map.update!(acc, :labels, &Map.put(&1, k, v))
      end
    end)
  end

  defp update_sub_metric(sub_metric, "bucket", quantiles) when map_size(quantiles) == 0 do
    sub_metric
  end

  defp update_sub_metric(sub_metric, "bucket", quantiles) do
    Map.update(sub_metric, :quantiles, quantiles, &Map.merge(&1, quantiles))
  end

  defp update_sub_metric(sub_metric, "count", val) do
    Map.put(sub_metric, :count, val)
  end

  defp update_sub_metric(sub_metric, "sum", val) do
    Map.put(sub_metric, :sum, val)
  end

  defp normalize(map_of_type_name_metrics) do
    name1 =
      case Map.fetch(map_of_type_name_metrics, :name) do
        {:ok, value} -> String.trim(value)
        :error -> "empty_name1"
      end

    type1 =
      case Map.fetch(map_of_type_name_metrics, :type) do
        {:ok, value} -> value
        :error -> "empty_type"
      end

    metrics1 =
      case Map.fetch(map_of_type_name_metrics, :metrics) do
        {:ok, value} ->
          Enum.map(value, &normalize_metrics/1)

        :error ->
          default_values(type1)
      end

    %{name: name1, type: type1, metrics: metrics1}
  end

  defp default_values("histogram"), do: %{count: 0, sum: 0}
  defp default_values("gauge"), do: [%{value: 0}]
  defp default_values(_), do: [%{value: 0}]

  defp normalize_metrics({labels, inner_values}) when map_size(labels) == 0 do
    inner_values
  end

  defp normalize_metrics({labels, inner_values}) do
    data = Map.put(inner_values, :labels, labels)
    data
  end

  @doc """
  Reduce metrics to build a map of metrics for several type such as histogram and gauges to simplify the structure

  ## Examples

      iex> [
      ...>   %{
      ...>      name: "archethic_contract_parsing_duration",
      ...>      type: "histogram",
      ...>      metrics: [%{quantiles: %{"\\"0.001\\"" => "105"}, count: 2, sum: 10.0 } ]
      ...>    },
      ...>    %{
      ...>       metrics: [%{value: 1589609}],
      ...>       name: "vm_memory_atom",
      ...>       type: "gauge"
      ...>     },
      ...> ] |> Parser.reduce_metrics()
      %{
        "archethic_contract_parsing_duration" => %{count: 2, sum: 10.0},
        "vm_memory_atom" => 1589609
      }
  """
  @spec reduce_metrics(list(metric())) ::
          %{String.t() => %{count: number(), sum: number()} | number()}
  def reduce_metrics(metrics) do
    Enum.reduce(metrics, %{}, fn
      metric = %{type: "histogram"}, acc ->
        Map.merge(acc, map_histogram(metric))

      metric = %{type: "gauge"}, acc ->
        Map.merge(acc, map_gauge(metric))

      metric = %{type: "counter"}, acc ->
        Map.merge(acc, map_counter(metric))
    end)
  end

  defp map_counter(%{name: name, metrics: metrics}) do
    metrics =
      Enum.reduce(metrics, 0, fn _, acc ->
        acc + 1
      end)

    %{name => metrics}
  end

  defp map_gauge(%{name: name, metrics: [metric | _]}) do
    value = Map.get(metric, :value, 0)
    %{name => value}
  end

  # Fetches the metric name and count,sum of the given histogram metrics.
  # It also calculates average across multiple labels for histogram_metrics
  defp map_histogram(%{name: name, metrics: metrics}) do
    metrics =
      Enum.reduce(metrics, %{sum: 0.0, count: 0}, fn %{count: count, sum: sum}, acc ->
        acc
        |> Map.update!(:count, &(&1 + count))
        |> Map.update!(:sum, &(&1 + sum))
      end)

    %{name => metrics}
  end
end
