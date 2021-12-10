defmodule ArchEthic.Metrics.MetricsDataParser do
  @moduledoc """
  MetricsDataParser.run() parses metrics data and convert into structured data
  """


def run(content) do
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
          bucket_extract_update(acc, key, labels, value)

        nil ->
          case Regex.run(~r/^#{metric_name} (.*)$/, content) do
            [_, value] ->
              put_in(acc, [:current, Access.key(:metrics, %{}), %{}], %{value: value})

            _ ->
              acc
          end
      end
    end

    def bucket_extract_update(acc, key, labels, value) do
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

    defp update_sub_metric(sub_metric, other, val) do
      Map.put(sub_metric, other, val)
    end

    defp normalize(%{name: name, type: type, metrics: metrics}) do
      %{
        name: name,
        type: type,
        metrics: Enum.map(metrics, &normalize_metrics/1)
      }
    end

    defp normalize_metrics({labels, inner_values}) when map_size(labels) == 0 do
      inner_values
    end

    defp normalize_metrics({labels, inner_values}) do
      Map.put(inner_values, :labels, labels)
    end
  end
