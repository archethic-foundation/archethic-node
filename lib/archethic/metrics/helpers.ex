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
  Filters out metrics that are not required ,Before reporting to the poller
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

     retrieve_node_ip_address() -> [ip , ip ,ip]


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
    services().retrieve_node_ip_address()
    |> Task.async_stream(
      &(services().establish_connection(&1)
        |> services().request_and_wait_for_response())
    )
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

  defp services() do
    Application.get_env(:archethic, :metrics_endpoint)
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
  Fetches the metric name and count,sum of the given histogram metrics.
  Fetches the metric name and metic value for guage metrics.

  ## Examples

      iex> [ %{ name: "archethic_contract_parsing_duration" , type: "histogram",
      ...>      metrics: [%{:quantiles =>%{"\\"0.001\\"" => "105"} , "count" => "2" , "sum" => "10" } ]},
      ...>        %{metrics: [%{value: "1589609"}], name: "vm_memory_atom", type: "gauge"},
      ...>     ]|>ArchEthic.Metrics.Helpers.retrieve_metric_parameter_data()
      [%{"archethic_contract_parsing_duration" => %{count: 2.0, sum: 10.0}}, %{"vm_memory_atom" => 1589609.0}]
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

  @doc """
  Method combines maps of metrics of different nodes into a single map of respective metrics

  ## Examples
      iex> [
      ...>   %{"vm_memory_atom" => 100.0},
      ...>   %{"archethic_p2p_send_message_duration" => %{count: 100, sum: 10}},
      ...>   %{"vm_memory_atom" => 200.0},
      ...>   %{"archethic_p2p_send_message_duration" => %{count: 200, sum: 20}},
      ...>   %{"vm_memory_atom" => 300.0},
      ...>   %{"archethic_p2p_send_message_duration" => %{count: 300, sum: 30}}
      ...> ]|>ArchEthic.Metrics.Helpers.aggregate_sum_n_count_n_value()
      %{
        "archethic_mining_full_transaction_validation_duration" => %{count: 0, sum: 0},
        "archethic_mining_proof_of_work_duration" => %{count: 0, sum: 0},
        "archethic_p2p_send_message_duration" => %{count: 600, sum: 60},
        "tps" => %{count: 0, sum: 0},
        "vm_memory_atom" => 600.0
      }

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

  ## Examples
      iex> %{
      ...>   "archethic_mining_full_transaction_validation_duration" => %{count: 5, sum: 10},
      ...>   "archethic_p2p_send_message_duration" => %{count: 600, sum: 60},
      ...>   "tps" => %{count: 5, sum: 50 },
      ...>   "vm_memory_atom" => 600.0
      ...> }|>ArchEthic.Metrics.Helpers.calculate_network_points()
      [
         %{"archethic_mining_full_transaction_validation_duration" => 2.0},
         %{"archethic_p2p_send_message_duration" => 0.1},
         %{"tps" => 10.0},
         %{"vm_memory_atom" => 600.0}
      ]
  """
  def calculate_network_points(map_of_metrics) do
    Enum.map(map_of_metrics, fn {metric_name, count_or_sum_or_value_map} ->
      case count_or_sum_or_value_map do
        %{count: count, sum: sum} -> fetch_avg(metric_name, count, sum)
        value -> %{metric_name => value}
      end
    end)
  end

  @doc """
  Reduces to a single map of metrics rather than list of maps of metrics

  ## Examples

      iex>[
      ...>   %{"archethic_mining_full_transaction_validation_duration" => 2.0},
      ...>   %{"archethic_p2p_send_message_duration" => 0.1},
      ...>   %{"tps" => 10.0},
      ...>   %{"vm_memory_atom" => 600.0}
      ...>]|>ArchEthic.Metrics.Helpers.reduce_to_single_map()
      %{
            "archethic_mining_full_transaction_validation_duration" => 2.0,
            "archethic_p2p_send_message_duration" => 0.1,
            "tps" => 10.0,
            "vm_memory_atom" => 600.0
        }
  """
  def reduce_to_single_map(data_list_of_maps) do
    Enum.reduce(data_list_of_maps, fn a, b ->
      Map.merge(a, b, fn _key, a1, a2 ->
        a1 + a2
      end)
    end)
  end

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

  @doc """
  Tampered to change the required metrics.
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

      %{metrics: _, name: "vm_memory_atom", type: _} ->
        true

      %{metrics: _, name: _, type: _} ->
        false

      _ ->
        false
    end
  end

  @doc """
  Returns a default for Metric Poller
  """
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
  Returns metric default value for accumulator
  """
  def get_metric_default_value() do
    %{
      "tps" => %{count: 0, sum: 0},
      "archethic_mining_full_transaction_validation_duration" => %{count: 0, sum: 0},
      "archethic_p2p_send_message_duration" => %{count: 0, sum: 0},
      "archethic_mining_proof_of_work_duration" => %{count: 0, sum: 0},
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
      "vm_memory_atom" => 0
    }
  end

  # Poller Helper functions
  @doc """
  Holds Poller default/initial state
  """
  def poller_default_state() do
    %{pid_refs: %{}, data: get_client_metric_default_value()}
  end

  @doc """
  Method pushes metric/new_state updates to registered Live Processes
  """
  def dipatch_updates(%{data: data, pid_refs: pid_refs}) do
    pid_refs
    |> Task.async_stream(fn {pid_k, _pid_v} -> send(pid_k, {:update_data, data}) end)
    |> Stream.run()
  end

  @doc """
  When a new Live-View Procces is created it Add that pid to state: pid_ref
  , to monitor and dispatch updates to it.
  """
  def register_process(pid, state) do
    new_state = %{state | pid_refs: Map.put(state.pid_refs, pid, nil)}
    dipatch_updates(new_state)
    _mref = Process.monitor(pid)
    new_state
  end

  @doc """
  When a Live process terminates it is removed from the new_pid_refs
  to stop dipacthing updates to it.
  """
  def deregister_process(from_pid, state) do
    {_removed_pid, new_pid_refs} = Map.pop(state.pid_refs, from_pid)
    %{state | pid_refs: new_pid_refs}
  end

  def process_new_state(current_state) do
    case Enum.empty?(current_state.pid_refs) do
      false ->
        dipatch_updates(current_state)
        %{data: get_new_data(), pid_refs: current_state.pid_refs}

      true ->
        current_state
    end
  end

  defp get_new_data() do
    network_collector()
  end
end
