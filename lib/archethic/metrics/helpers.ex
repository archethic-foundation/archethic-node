defmodule ArchEthic.Metrics.Helpers do
  @moduledoc """
  Provides helper methods & data in transformation of metrics.
  """
  require Logger

  @doc """
  Converts to map of metrics using
  Main method to transform metrics.Method to do any remaining transformations at last.
  """
  def network_collector() do
    data = Enum.filter(retrieve_network_metrics(), fn {key, _val} -> req_metrics(key) end)
    Enum.into(data, %{})
  end

  @doc """
  Filters out metrics that are not required.
  """
  def req_metrics(data) do
    case data do
      "archethic_mining_proof_of_work_duration" -> true
      "archethic_mining_full_transaction_validation_duration" -> true
      "archethic_p2p_send_message_duration" -> true
      "tps" -> true
      _ -> false
    end
  end

  @doc """
  Responsible for retrieving network metrics.

  Purpose of this Pipline Method
  |>Enum.reduce([], fn x, acc -> Enum.concat(acc, x) end)
  Expected Pipline Input :
  [[node1_metrics],[node2_metrics],[node3_metrics],...]
  Recieves list of list of metrics , where each metric is a map
  with name and count and sum for histogram type metrics , for
  metric type guage it is a map with %{"metric_name" => 0}.
   [
     [%{"metric_name" => %{ count: 0, sum: 0 }} , %{"metric_name" => %{count: 0, sum: }}], ...],
     [%{"metric_name" => %{ count: 0, sum: 0 }} , %{"metric_name" => %{count: 0, sum: }}], ...],
     ...]
  Expected this.Pipline Output :
    [ %{"metric_name" => %{ count: 0, sum: 0 }} , %{"metric_name" => 0} , %{ } , %{ } , %{ } ...]
    list of metrics , where metric is a map with name and count and sum for histogram type metrics ,
    for metric type guage it is a map with %{"metric_name" => 0}.
    The output is ready to be merged with similar metrics from another nodes.
  """
  def retrieve_network_metrics() do
    retrieve_node_ip_address()
    |> Task.async_stream(fn each_node_ip -> establish_connection_to_node(each_node_ip) end)
    |> remove_noise()
    |> Stream.map(&ArchEthic.Metrics.Parser.run/1)
    |> Stream.map(&filter_metrics/1)
    |> Stream.map(&retrieve_metric_parameter_data/1)
    |> inject_tps()
    |> Enum.reduce([], fn x, acc -> Enum.concat(acc, x) end)
    |> aggregate_sum_n_count_n_value()
    |> calculate_network_points()
    |> reduce_to_single_map()
  end

  @doc """
  """
  def inject_tps(list_of_lists_of_metric_maps) do
    Enum.map(list_of_lists_of_metric_maps, fn list_of_maps ->
      count_by_sum = Enum.reduce(list_of_maps, 1, fn map, acc -> get_tps(map, acc) end)

      [%{"tps" => %{count: 1, sum: count_by_sum}} | list_of_maps]
    end)
  end

  def get_tps(map, acc) do
    case map do
      %{"archethic_mining_full_transaction_validation_duration" => %{count: count, sum: sum}} ->
        case sum == 0 do
          true -> 0
          false -> count / sum
        end

      _ ->
        acc
    end
  end

  @doc """
  Establishes connection at port 40_000 for given node_ip.In case of error, returns empty list.
  """
  def establish_connection_to_node(ip) do
    case Mint.HTTP.connect(:http, ip, 40_000) do
      {:ok, conn} -> contact_endpoint_for_data(conn)
      _ -> []
    end
  end

  @doc """
  Send get request to /metrics endpoint of a node.
  Returns response in case of success, otherwise returns empty list.
  """
  def contact_endpoint_for_data(conn) do
    {:ok, conn, _request_ref} = Mint.HTTP.request(conn, "GET", "/metrics", [], [])

    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            {:ok, _conn_close} = Mint.HTTP.close(conn)
            responses

          _unknown ->
            []
        end
    end
  end

  @doc """
  To keep only the required metrics.
  """
  def filter_metrics(data) do
    Enum.filter(data, metric_filter())
  end

  @doc """
  Returns a predicate to filter metrics.
  """
  def metric_filter() do
    fn
      %{metrics: _, name: "archethic_mining_proof_of_work_duration", type: _} ->
        true

      %{metrics: _, name: "archethic_mining_full_transaction_validation_duration", type: _} ->
        true

      %{metrics: _, name: "archethic_p2p_send_message_duration", type: _} ->
        true

      # %{metrics: _, name: "archethic_election_validation_nodes_duration", type: _} ->
      #   true

      # %{metrics: _, name: "archethic_election_storage_nodes_duration", type: _} ->
      #   true

      # %{metrics: _, name: "archethic_mining_pending_transaction_validation_duration", type: _} ->
      #   true

      # %{metrics: _, name: "archethic_contract_parsing_duration", type: _} ->
      #   true

      # %{metrics: _, name: "archethic_mining_fetch_context_duration", type: _} ->
      #   true

      # %{metrics: _, name: "archethic_db_duration", type: _} ->
      #   true

      # %{metrics: _, name: "archethic_self_repair_duration", type: _} ->
      #   true

      # %{metrics: _, name: "vm_total_run_queue_lengths_io", type: _} ->
      #   true

      # %{metrics: _, name: "vm_total_run_queue_lengths_cpu", type: _} ->
      #   true

      # %{metrics: _, name: "vm_total_run_queue_lengths_total", type: _} ->
      #   true

      # %{metrics: _, name: "vm_system_counts_process_count", type: _} ->
      #   true

      # %{metrics: _, name: "vm_system_counts_port_count", type: _} ->
      #   true

      # %{metrics: _, name: "vm_system_counts_atom_count", type: _} ->
      #   true

      # %{metrics: _, name: "vm_memory_total", type: _} ->
      #   true

      # %{metrics: _, name: "vm_memory_system", type: _} ->
      #   true

      # %{metrics: _, name: "vm_memory_processes_used", type: _} ->
      #   true

      # %{metrics: _, name: "vm_memory_processes", type: _} ->
      #   true

      # %{metrics: _, name: "vm_memory_ets", type: _} ->
      #   true

      # %{metrics: _, name: "vm_memory_code", type: _} ->
      #   true

      # %{metrics: _, name: "vm_memory_binary", type: _} ->
      #   true

      # %{metrics: _, name: "vm_memory_atom_used", type: _} ->
      #   true

      # %{metrics: _, name: "vm_memory_atom", type: _} ->
      #   true

      %{metrics: _, name: _, type: _} ->
        false

      _ ->
        false
    end
  end

  @doc """
  Recieves [[node1_metrics],[node2_metrics],[node3_metrics],...]
  Recieves List of list of metrics , each metric is a map with name and type.
  [[node1_metrics] , [node2_metrics] , ... ] =>
    [
       [ %{metrics: [],name: "metric_name", type: "metric_name"}] ,
       [ %{metrics: [],name: "metric_name", type: "metric_name"}] ,
       ...
   ]
   Returns [[node1_metrics],[node2_metrics],[node3_metrics],...]
   Returns list of list of metrics , where each metric is a map
   with name and count and sum for histogram type metrics , for
   metric type guage it is a map with %{"metric_name" => 0}.
   [
     [%{"metric_name" => %{ count: 0, sum: 0 }} , %{"metric_name" => %{count: 0, sum: }}], ...],
     [%{"metric_name" => %{ count: 0, sum: 0 }} , %{"metric_name" => %{count: 0, sum: }}], ...],
     ...]
  """
  def retrieve_metric_parameter_data(data) do
    Enum.map(data, fn each_metric ->
      case each_metric.type do
        "histogram" -> fetch_histogram_sum_count(each_metric)
        "gauge" -> fetch_guage_value(each_metric)
      end
    end)
  end

  def calculate_points(list_of_map_of_metric_with_name_count_sum_value) do
    Enum.map(
      list_of_map_of_metric_with_name_count_sum_value,
      fn metric_map ->
        [{metric_name, count_or_sum_or_value_map}] = metric_map |> Map.to_list()

        case count_or_sum_or_value_map do
          %{count: count, sum: sum} ->
            fetch_avg(metric_name, count, sum)

          value ->
            %{metric_name => value}
        end
      end
    )
  end

  def fetch_avg(metric_name, count, sum) do
    avg =
      case count == 0 do
        true -> 0
        false -> sum / count
      end

    %{metric_name => avg}
  end

  def fetch_guage_value(single_metric_map) do
    [value_map | _tail] = single_metric_map.metrics

    {guage_value, _} =
      case Map.fetch(value_map, :value) do
        {:ok, value} -> Float.parse(value)
        :error -> {0, ""}
      end

    %{single_metric_map.name => guage_value}
  end

  def fetch_histogram_sum_count(single_metric_map) do
    list2 =
      Enum.map(single_metric_map.metrics, fn inner_data ->
        {sum, count} = get_sum_count(inner_data)
        %{sum: sum, count: count}
      end)

    %{
      single_metric_map.name => %{
        sum: Enum.reduce(list2, 0, fn data_tuple, acc -> acc + data_tuple.sum end),
        count: Enum.reduce(list2, 0, fn data_tuple, acc -> acc + data_tuple.count end)
      }
    }
  end

  def get_sum_count(inner_data) do
    {count, _} =
      case Map.fetch(inner_data, "count") do
        {:ok, value} -> Float.parse(value)
        :error -> {0, ""}
      end

    {sum, _} =
      case Map.fetch(inner_data, "sum") do
        {:ok, value} -> Float.parse(value)
        :error -> {0, ""}
      end

    {sum, count}
  end

  def reduce_to_single_map(data_list_of_maps) do
    Enum.reduce(data_list_of_maps, fn a, b ->
      Map.merge(a, b, fn _key, a1, a2 ->
        a1 + a2
      end)
    end)
  end

  def retrieve_node_ip_address() do
    Enum.map(ArchEthic.P2P.list_nodes(), fn node_details ->
      ip = :inet.ntoa(node_details.ip)
      "#{ip}"
    end)
  end

  def remove_noise(data) do
    data
    |> Stream.map(fn {:ok, result} -> result end)
    |> Stream.filter(&remove_blank_responses/1)
    |> Stream.map(&retrieve_data_from_response/1)
  end

  def remove_blank_responses(result) do
    case result do
      [] -> false
      _ -> true
    end
  end

  def retrieve_data_from_response(data) do
    list =
      Enum.filter(data, fn dataelement ->
        case dataelement do
          {:data, _, _} -> true
          _ -> false
        end
      end)

    list2 = Enum.map(list, fn x -> elem(x, 2) end)
    [head | _tail] = list2
    head
  end

  def get_client_metric_default_value() do
    %{
      "archethic_mining_full_transaction_validation_duration" => 0,
      "archethic_mining_proof_of_work_duration" => 0,
      "archethic_p2p_send_message_duration" => 0,
      "tps" => 0
      # "archethic_election_validation_nodes_duration" => 0,
      # "archethic_election_storage_nodes_duration" => 0,
      # "archethic_mining_pending_transaction_validation_duration" => 0,
      # "archethic_contract_parsing_duration" => 0,
      # "archethic_mining_fetch_context_duration" => 0,
      # "archethic_db_duration" => 0,
      # "archethic_self_repair_duration" => 0,
      # "vm_total_run_queue_lengths_io" => 0,
      # "vm_total_run_queue_lengths_cpu" => 0,
      # "vm_total_run_queue_lengths_total" => 0,
      # "vm_system_counts_process_count" => 0,
      # "vm_system_counts_port_count" => 0,
      # "vm_system_counts_atom_count" => 0,
      # "vm_memory_total" => 0,
      # "vm_memory_system" => 0,
      # "vm_memory_processes_used" => 0,
      # "vm_memory_processes" => 0,
      # "vm_memory_ets" => 0,
      # "vm_memory_code" => 0,
      # "vm_memory_binary" => 0,
      # "vm_memory_atom_used" => 0,
      # "vm_memory_atom" => 0
    }
  end

  @doc """
  """
  def get_metric_default_value() do
    %{
      "tps" => %{count: 0, sum: 0},
      "archethic_mining_full_transaction_validation_duration" => %{count: 0, sum: 0},
      "archethic_p2p_send_message_duration" => %{count: 0, sum: 0},
      "archethic_mining_proof_of_work_duration" => %{count: 0, sum: 0}
      # "archethic_election_validation_nodes_duration" => %{count: 0, sum: 0},
      # "archethic_election_storage_nodes_duration" => %{count: 0, sum: 0},
      # "archethic_mining_pending_transaction_validation_duration" => %{count: 0, sum: 0},
      # "archethic_contract_parsing_duration" => %{count: 0, sum: 0},
      # "archethic_mining_fetch_context_duration" => %{count: 0, sum: 0},
      # "archethic_db_duration" => %{count: 0, sum: 0},
      # "archethic_self_repair_duration" => 0,
      # "vm_total_run_queue_lengths_io" => 0,
      # "vm_total_run_queue_lengths_cpu" => 0,
      # "vm_total_run_queue_lengths_total" => 0,
      # "vm_system_counts_process_count" => 0,
      # "vm_system_counts_port_count" => 0,
      # "vm_system_counts_atom_count" => 0,
      # "vm_memory_total" => 0,
      # "vm_memory_system" => 0,
      # "vm_memory_processes_used" => 0,
      # "vm_memory_processes" => 0,
      # "vm_memory_ets" => 0,
      # "vm_memory_code" => 0,
      # "vm_memory_binary" => 0,
      # "vm_memory_atom_used" => 0,
      # "vm_memory_atom" => 0
    }
  end

  @doc """
  Method combines maps of metrics of different nodes into a single map of respective metrics
  Expected Input :
    [ %{"metric_name" => %{ count: 0, sum: 0 }} , %{"metric_name" => 0} , %{ } , %{ } , %{ } ...]
    list of metrics , where metric is a map with name and count and sum for histogram type metrics ,
    for metric type guage it is a map with %{"metric_name" => 0}.
  Expected Output :


  """
  def aggregate_sum_n_count_n_value(combined_list_of_map_metric) do
    Enum.reduce(combined_list_of_map_metric, get_metric_default_value(), fn metric_map, acc ->
      [{metric_name, count_or_sum_or_value_map}] = metric_map |> Map.to_list()

      case count_or_sum_or_value_map do
        %{count: count, sum: sum} -> update_histogram_acc(metric_name, count, sum, acc)
        value -> update_guage_acc(metric_name, value, acc)
      end
    end)
  end

  @doc """
    I/P map of metrics with count n sum and n value
    O/P list of map of metrics with avg and value
  """
  def calculate_network_points(map_of_metrics) do
    Enum.map(map_of_metrics, fn {metric_name, count_or_sum_or_value_map} ->
      case count_or_sum_or_value_map do
        %{count: count, sum: sum} -> fetch_avg(metric_name, count, sum)
        value -> %{metric_name => value}
      end
    end)
  end

  # [head | _tail] = Map.keys(x)
  # csum = get_in(acc, [head, :sum])
  # ccount = get_in(acc, [head, :count])
  # sum = get_in(x, [head, :sum])
  # count = get_in(x, [head, :count])
  # put_in(put_in(acc, [head, :sum], csum + sum), [head, :count], ccount + count)

  def update_histogram_acc(metric_name, count, sum, acc) do
    cummlative_sum = get_in(acc, [metric_name, :sum])
    cummlative_count = get_in(acc, [metric_name, :count])

    put_in(
      put_in(acc, [metric_name, :sum], cummlative_sum + sum),
      [metric_name, :count],
      cummlative_count + count
    )
  end

  def update_guage_acc(metric_name, value, acc) do
    cummlative_value = get_in(acc, [metric_name])
    put_in(acc, [metric_name], cummlative_value + value)
  end
end
