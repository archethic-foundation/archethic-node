defmodule ArchEthic.Metrics.Parser do
  @moduledoc """
  MetricsDataParser.run() parses metrics data and convert into structured data
  """

  @doc """
  Convert multi-line metrics data into structured data

  ## Examples

          iex> data =
          ...>     """
          ...>     HELP archethic_self_repair_duration
          ...>     # TYPE archethic_self_repair_duration gauge
          ...>     archethic_self_repair_duration 3.610969045
          ...>     # HELP archethic_db_duration
          ...>     # TYPE archethic_db_duration histogram
          ...>     archethic_db_duration_sum{query='write_transaction_chain'} 5.5
          ...>     archethic_db_duration_count{query='write_transaction_chain'} 93
          ...>     archethic_db_duration_sum{query='get_transaction_chain'} 1161.8
          ...>     archethic_db_duration_count{query='get_transaction_chain'} 5284
          ...>     archethic_db_duration_sum{query='write_transaction'} 7.3
          ...>     archethic_db_duration_count{query='write_transaction'} 1211
          ...>     archethic_db_duration_bucket{query='get_transaction',le='+Inf'} 2061
          ...>     archethic_db_duration_sum{query='get_transaction'} 15.235701532000004
          ...>     archethic_db_duration_count{query='get_transaction'} 2061
          ...>     # HELP archethic_contract_parsing_duration
          ...>     # TYPE archethic_contract_parsing_duration histogram
          ...>     archethic_contract_parsing_duration_bucket{le='0.001'} 153
          ...>     archethic_contract_parsing_duration_bucket{le='+Inf'} 177
          ...>     archethic_contract_parsing_duration_sum 0.12
          ...>     archethic_contract_parsing_duration_count 177
          ...>     # HELP archethic_mining_full_transaction_validation_duration
          ...>     # TYPE archethic_mining_full_transaction_validation_duration histogram
          ...>     archethic_mining_full_transaction_validation_duration_bucket{le='0.01'} 0
          ...>     archethic_mining_full_transaction_validation_duration_bucket{le='+Inf'} 85
          ...>     archethic_mining_full_transaction_validation_duration_sum 31.9
          ...>     archethic_mining_full_transaction_validation_duration_count 85
          ...>     # HELP archethic_mining_fetch_context_duration
          ...>     # TYPE archethic_mining_fetch_context_duration histogram
          ...>     archethic_mining_fetch_context_duration_sum 8.2
          ...>     archethic_mining_fetch_context_duration_count 88
          ...>     # HELP archethic_mining_pending_transaction_validation_duration
          ...>     # TYPE archethic_mining_pending_transaction_validation_duration histogram
          ...>     archethic_mining_pending_transaction_validation_duration_bucket{le='0.001'} 20
          ...>     archethic_mining_pending_transaction_validation_duration_bucket{le='+Inf'} 87
          ...>     archethic_mining_pending_transaction_validation_duration_sum 11.4
          ...>     archethic_mining_pending_transaction_validation_duration_count 87
          ...>     # HELP archethic_election_storage_nodes_duration
          ...>     # TYPE archethic_election_storage_nodes_duration histogram
          ...>     archethic_election_storage_nodes_duration_bucket{nb_nodes='1',le='+Inf'} 1074
          ...>     archethic_election_storage_nodes_duration_sum{nb_nodes='1'} 0.032
          ...>     archethic_election_storage_nodes_duration_count{nb_nodes='1'} 1074
          ...>     archethic_election_storage_nodes_duration_bucket{nb_nodes='2',le='0.001'} 120
          ...>     archethic_election_storage_nodes_duration_sum{nb_nodes='2'} 0.011
          ...>     archethic_election_storage_nodes_duration_count{nb_nodes='2'} 122
          ...>     archethic_election_storage_nodes_duration_sum{nb_nodes='3'} 3.11
          ...>     archethic_election_storage_nodes_duration_count{nb_nodes='3'} 45719
          ...>     # HELP vm_memory_atom
          ...>     # TYPE vm_memory_atom gauge
          ...>     vm_memory_atom 1589609
          ...>     """
          iex> length(ArchEthic.Metrics.Parser.run(data))==Enum.count(ArchEthic.Metrics.Parser.run(data),fn x ->
          ...>     case x do
          ...>       %{metrics: [%{value: _ }], name: _ ,type: "gauge"} -> true
          ...>       %{ metrics: [%{:quantiles => _ , "count" => _ ,"sum" => _ }],name: _ ,type: "histogram"  } -> true
          ...>       %{ name: _ , type: "histogram" , metrics:
          ...>        [%{:labels => %{"nb_nodes" => _ },:quantiles => _ ,"count" => _ ,"sum" => _ },
          ...>       %{:labels => %{"nb_nodes" => _ },:quantiles => _, "count" => _,"sum" => _   }| _ ],    } ->  true
          ...>       %{name: _ , type: "histogram" , metrics:
          ...>        [ %{:labels => %{"query" => _ },:quantiles => _ , "count" => _ ,"sum" => _  },
          ...>       %{:labels => %{"query" => _}, :quantiles => _ ,  "count" =>  _ , "sum" => _ } | _  ]}  -> true
          ...>       %{ name: _ , type: "histogram" ,metrics:
          ...>        [   %{:labels => %{"message" => _ }, :quantiles => _ ,   "count" => _ ,  "sum" => _},
          ...>       %{ :labels => %{"message" => _ },:quantiles =>  _ ,   "count" => _ ,    "sum" => _}       |_]} -> true
          ...>        _ -> false
          ...>     end
          ...> end)
          true

  """
  def run(content) do
    content
    |> String.split(" \n", trim: true)
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
          default_according_to_guage_histogram(type1)
      end

    %{name: name1, type: type1, metrics: metrics1}
  end

  def default_according_to_guage_histogram(data) do
    case data do
      "histogram" -> %{"count" => "0", "sum" => "0"}
      "gauge" -> [%{value: "0"}]
      _ -> [%{value: "0"}]
    end
  end

  defp normalize_metrics({labels, inner_values}) when map_size(labels) == 0 do
    inner_values
  end

  defp normalize_metrics({labels, inner_values}) do
    Map.put(inner_values, :labels, labels)
  end
end
