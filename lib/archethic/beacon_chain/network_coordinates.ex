defmodule Archethic.BeaconChain.NetworkCoordinates do
  @moduledoc """
  Network coordinates is a way to map latency between nodes and used to determine the closest nodes
  """

  @digits ["F", "E", "D", "C", "B", "A", "9", "8", "7", "6", "5", "4", "3", "2", "1", "0"]

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Subset.SummaryCache
  alias Archethic.BeaconChain.Subset.P2PSampling

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetNetworkStats
  alias Archethic.P2P.Message.NetworkStats

  alias Archethic.SelfRepair
  alias Archethic.Utils

  require Logger

  @doc """
  Return the timeout to determine network patches
  It is equivalent to 4m30s in production. 4.5s in dev.
  It must be called only when creating the beacon summary
  """
  def timeout() do
    SelfRepair.next_repair_time()
    |> DateTime.diff(DateTime.utc_now())
    # We take 10% of the next repair time to determine the timeout
    |> Kernel.*(0.9)
    |> Kernel.*(1000)
    |> round()
  end

  @doc """
  Compute the network patch based on the matrix latencies

  The matrix must be an:
  - Hollow matrix (all diagonal elements should all be 0)
  - symmetric (for all i and for all j M[i][j] = M[j][i])
  - all off-diagonal elements must be positive (i!=j)

  We use the multidimensional scaling  to transform the matrix into x, y coordinates from matrix factorization using
  eigenvalues and eigenvectors to find their corresponding coordinates.

  Then we transform the coordinates into hexadecimal digits
  """
  @spec get_patch_from_latencies(Nx.Tensor.t()) :: list(String.t())
  def get_patch_from_latencies(matrix = %Nx.Tensor{}) do
    if Nx.size(matrix) > 1 do
      start_time = System.monotonic_time()

      network_patches =
        matrix
        |> get_matrix_coordinates()
        |> get_patch_digits()

      :telemetry.execute(
        [:archethic, :beacon_chain, :network_coordinates, :compute_patch],
        %{
          duration: System.monotonic_time() - start_time
        },
        %{matrix_size: Nx.size(matrix)}
      )

      network_patches
    else
      []
    end
  end

  @doc """
  Computes the matrix coordinates from latency matrix between nodes

  It returns a new matrix will the x, y coordinates of each node's network coordinate
  """
  @spec get_matrix_coordinates(Nx.Tensor.t()) :: Nx.Tensor.t()
  def get_matrix_coordinates(matrix = %Nx.Tensor{}) do
    matrix
    |> Nx.as_type(:f64)
    |> matrix_multidimensional_scaling()
    |> get_coordinates()
  end

  defp matrix_multidimensional_scaling(matrix_tensor) do
    matrix_size = Nx.size(matrix_tensor[0])
    d_squared = Nx.pow(matrix_tensor, 2)

    d_mean_squared = Nx.mean(d_squared)
    # Get the mean of all the rows
    di_mean = d_squared |> Nx.mean(axes: [1])
    # Get the mean of all the columns
    dj_mean = d_squared |> Nx.mean(axes: [0])

    Enum.map(0..(matrix_size - 1), fn i ->
      Enum.map(0..(matrix_size - 1), fn j ->
        dij_squared = d_squared[i][j]
        # Square the column's mean at i
        di_mean_squared = di_mean[i]
        # Square the row's mean at j
        dj_mean_squared = dj_mean[j]

        dij_squared
        |> Nx.subtract(di_mean_squared)
        |> Nx.subtract(dj_mean_squared)
        |> Nx.add(d_mean_squared)
        |> Nx.multiply(Nx.tensor(-0.5, type: {:f, 64}))
      end)
      |> Nx.stack()
    end)
    |> Nx.stack()
  end

  defp get_coordinates(mds_matrix) do
    {eigen_values, eigen_vectors} = Nx.LinAlg.eigh(mds_matrix)

    sorted_eigen_values =
      eigen_values
      |> Nx.to_list()
      |> Enum.with_index()
      |> Enum.sort_by(fn {val, _} -> val end, :desc)

    top_eigen_values =
      sorted_eigen_values
      |> Enum.take(2)
      |> Enum.map(fn {val, _} -> abs(val) end)
      |> Nx.tensor()
      |> Nx.sqrt()

    indexes = Enum.map(sorted_eigen_values, fn {_, index} -> index end)

    top_eigen_vectors =
      eigen_vectors
      |> Nx.to_list()
      |> Enum.map(fn row ->
        # Take in the same order as eigen values
        indexes
        |> Enum.take(2)
        |> Enum.map(&Enum.at(row, &1))
      end)
      |> Nx.tensor()

    Nx.multiply(top_eigen_vectors, top_eigen_values)
  end

  defp get_patch_digits(coordinates_matrix) do
    transposed_matrix = Nx.transpose(coordinates_matrix)
    x = transposed_matrix[0]
    y = transposed_matrix[1]

    max = Nx.max(Nx.abs(x), Nx.abs(y)) |> Nx.to_flat_list() |> Enum.max()

    v = 2.0 * max / 16.0

    x_size = Nx.size(x)

    Enum.map(0..(x_size - 1), fn i ->
      x_elem = x[i] |> Nx.to_number()
      y_elem = y[i] |> Nx.to_number()

      get_patch(x_elem, y_elem, v, max)
    end)
  end

  defp get_patch(x_elem, y_elem, v, max) when is_number(x_elem) and is_number(y_elem) do
    %{x: x, y: y} =
      Enum.reduce_while(0..15, %{x: "", y: ""}, fn j, acc ->
        if acc.x != "" and acc.y != "" do
          {:halt, acc}
        else
          new_acc =
            acc
            |> get_digit(:x, x_elem, j, max, v)
            |> get_digit(:y, y_elem, j, max, v)

          {:cont, new_acc}
        end
      end)

    # Default to "0" if no digit was found
    x = if x == "", do: "0", else: x
    y = if y == "", do: "0", else: y

    "#{x}#{y}"
  end

  # Handle NaN values
  defp get_patch(_x_elem, _y_elem, _v, _max) do
    Logger.warning("Error when calculating network patch, coordinates is NaN")
    "00"
  end

  defp get_digit(acc, coord_name, coord, digit_index, max, v) do
    lower_bound = max - v * (digit_index + 1.0)
    upper_bound = max - v * digit_index

    if coord >= lower_bound and coord <= upper_bound do
      Map.put(acc, coord_name, Enum.at(@digits, digit_index))
    else
      acc
    end
  end

  @doc """
  Fetch remotely the network stats for a given summary time

  This requests all the beacon nodes their aggregated network stats.
  A NxN latency matrix is then computed based on the network stats origins and targets
  """
  @spec fetch_network_stats(DateTime.t(), pos_integer()) :: Nx.Tensor.t()
  def fetch_network_stats(summary_time = %DateTime{}, timeout) do
    authorized_nodes = P2P.authorized_and_available_nodes(summary_time, true)

    sorted_node_list = P2P.list_nodes() |> Enum.sort_by(& &1.first_public_key)
    nb_nodes = length(sorted_node_list)
    beacon_nodes = get_beacon_nodes(summary_time, authorized_nodes)

    matrix = Nx.broadcast(0, {nb_nodes, nb_nodes})

    stream_network_stats(summary_time, beacon_nodes, timeout)
    # Aggregate stats per node to identify the sampling nodes
    |> aggregate_stats_per_subset()
    |> update_matrix_from_stats(matrix, sorted_node_list)
  end

  defp get_beacon_nodes(summary_time, authorized_nodes) do
    BeaconChain.list_subsets()
    |> Enum.reduce(MapSet.new(), fn subset, acc ->
      Election.beacon_storage_nodes(subset, summary_time, authorized_nodes)
      |> MapSet.new()
      |> MapSet.union(acc)
    end)
    |> MapSet.to_list()
  end

  defp stream_network_stats(summary_time, beacon_nodes, timeout) do
    Task.Supervisor.async_stream_nolink(
      Archethic.task_supervisors(),
      beacon_nodes,
      fn node ->
        P2P.send_message(node, %GetNetworkStats{summary_time: summary_time}, timeout)
      end,
      timeout: timeout + 1_000,
      ordered: false,
      on_timeout: :kill_task,
      max_concurrency: 256
    )
    |> Stream.filter(fn
      {:ok, {:ok, %NetworkStats{stats: stats}}} when map_size(stats) > 0 ->
        valid_stats?(stats)

      _ ->
        false
    end)
    |> Stream.map(fn {:ok, {:ok, %NetworkStats{stats: stats}}} -> stats end)
  end

  defp valid_stats?(stats) do
    Enum.all?(stats, fn {subset, nodes_stats} ->
      expected_stats_length = P2PSampling.list_nodes_to_sample(subset) |> length()

      Enum.map(nodes_stats, fn {_node, stats} -> length(stats) end)
      |> Enum.all?(&(&1 == expected_stats_length))
    end)
  end

  defp aggregate_stats_per_subset(stats) do
    stats
    |> Enum.flat_map(& &1)
    |> Enum.reduce(%{}, fn {subset, stats}, acc ->
      Enum.reduce(stats, acc, fn {node, stats}, acc ->
        Map.update(
          acc,
          subset,
          %{node => [stats]},
          &Map.update(&1, node, [stats], fn prev_stats -> [stats | prev_stats] end)
        )
      end)
    end)
    |> Enum.reduce(%{}, fn {subset, stats_by_node}, acc ->
      aggregated_stats_by_node =
        Enum.reduce(stats_by_node, %{}, fn {node, stats}, acc ->
          Map.put(acc, node, aggregate_stats(stats))
        end)

      Map.put(acc, subset, aggregated_stats_by_node)
    end)
  end

  defp aggregate_stats(stats) do
    stats
    |> Enum.zip()
    |> Enum.map(fn stats ->
      latency =
        stats
        |> Tuple.to_list()
        |> Enum.map(& &1.latency)
        |> Utils.mean()
        |> trunc()

      %{latency: latency}
    end)
  end

  defp update_matrix_from_stats(stats_by_subset, matrix, sorted_node_list) do
    Enum.reduce(stats_by_subset, matrix, fn {subset, stats}, acc ->
      sampling_nodes = P2PSampling.list_nodes_to_sample(subset)

      Enum.reduce(stats, acc, fn {node_public_key, stats}, acc ->
        beacon_node_index =
          Enum.find_index(sorted_node_list, &(&1.first_public_key == node_public_key))

        set_matrix_latency(acc, beacon_node_index, sampling_nodes, sorted_node_list, stats)
      end)
    end)
  end

  defp set_matrix_latency(
         matrix,
         beacon_node_index,
         sampling_nodes,
         sorted_node_list,
         stats
       ) do
    stats
    |> Enum.with_index()
    |> Enum.reduce(matrix, fn {%{latency: latency}, index}, acc ->
      sample_node = Enum.at(sampling_nodes, index)

      sample_node_index =
        Enum.find_index(
          sorted_node_list,
          &(&1.first_public_key == sample_node.first_public_key)
        )

      # Avoid update if it's the matrix diagonal
      if sample_node_index == beacon_node_index do
        acc
      else
        update_matrix(acc, beacon_node_index, sample_node_index, latency)
      end
    end)
  end

  defp update_matrix(matrix, beacon_node_index, sample_node_index, latency) do
    existing_points =
      matrix
      |> Nx.gather(
        Nx.tensor([
          [beacon_node_index, sample_node_index],
          [sample_node_index, beacon_node_index]
        ])
      )
      |> Nx.to_list()

    # Build symmetric matrix
    case existing_points do
      # Initialize cell
      [0, 0] ->
        Nx.indexed_put(
          matrix,
          Nx.tensor([
            [beacon_node_index, sample_node_index],
            [sample_node_index, beacon_node_index]
          ]),
          Nx.tensor([latency, latency])
        )

      # Take mean when latency differs
      [x, y] when (x >= 0 or y >= 0) and (latency != x or latency != y) ->
        mean_latency =
          if x > 0 do
            Archethic.Utils.mean([x, latency]) |> trunc()
          else
            Archethic.Utils.mean([latency, y]) |> trunc()
          end

        Nx.indexed_put(
          matrix,
          Nx.tensor([
            [beacon_node_index, sample_node_index],
            [sample_node_index, beacon_node_index]
          ]),
          Nx.tensor([mean_latency, mean_latency])
        )

      [^latency, ^latency] ->
        matrix
    end
  end

  @doc """
  Aggregate the network stats from the SummaryCache

  The summary cache holds the slots of the current summary identified by beacon node.
  Hence we can aggregate the view of one particular beacon node regarding the nodes sampled.

  The aggregation is using some weighted logistic regression.
  """
  @spec aggregate_network_stats(binary(), DateTime.t()) :: %{Crypto.key() => Slot.net_stats()}
  def aggregate_network_stats(subset, summary_time = %DateTime{}) when is_binary(subset) do
    summary_time
    |> SummaryCache.stream_slots(subset)
    |> Stream.filter(&match?({%Slot{p2p_view: %{network_stats: [_ | _]}}, _}, &1))
    |> Stream.map(fn
      {%Slot{p2p_view: %{network_stats: net_stats}}, node} ->
        {node, net_stats}
    end)
    |> Enum.reduce(%{}, fn {node, net_stats}, acc ->
      Map.update(acc, node, [net_stats], &(&1 ++ [net_stats]))
    end)
    |> Enum.map(fn {node, net_stats} ->
      aggregated_stats =
        net_stats
        |> Enum.zip()
        |> Enum.map(fn stats ->
          aggregated_latency =
            stats
            |> Tuple.to_list()
            |> Enum.map(& &1.latency)
            # The logistic regression is used to avoid impact of outliers
            # while providing a weighted approach to priorize the latest samples.
            |> weighted_logistic_regression()
            |> trunc()

          %{latency: aggregated_latency}
        end)

      {node, aggregated_stats}
    end)
    |> Enum.into(%{})
  end

  defp weighted_logistic_regression(list) do
    %{sum_weight: sum_weight, sum_weighted_list: sum_weighted_list} =
      list
      |> clean_outliers()
      # We want to apply a weight based on the tier of the latency
      |> Utils.chunk_list_in(3)
      |> weight_list()
      |> Enum.reduce(%{sum_weight: 0.0, sum_weighted_list: 0.0}, fn {weight, weighted_list},
                                                                    acc ->
        acc
        |> Map.update!(:sum_weighted_list, &(&1 + Enum.sum(weighted_list)))
        |> Map.update!(:sum_weight, &(&1 + weight * Enum.count(weighted_list)))
      end)

    sum_weighted_list / sum_weight
  end

  defp clean_outliers(list) do
    list_size = Enum.count(list)

    sorted_list = Enum.sort(list)

    # Compute percentiles (P80, P20) to remove the outliers
    p1 = (0.8 * list_size) |> trunc()
    p2 = (0.2 * list_size) |> trunc()

    max = Enum.at(sorted_list, p1)
    min = Enum.at(sorted_list, p2)

    Enum.map(list, fn
      x when x < min ->
        min

      x when x > max ->
        max

      x ->
        x
    end)
  end

  defp weight_list(list) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {list, i} ->
      # Apply weight of the tier
      weight = (i + 1) * (1 / 3)

      weighted_list = Enum.map(list, &(&1 * weight))

      {weight, weighted_list}
    end)
  end
end
