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

  alias Archethic.Utils

  alias Archethic.TaskSupervisor

  @doc """
  Compute the network patch based on the matrix latencies

  The matrix must be an:
  - Hollow matrix (all diagonal elements should all be 0)
  - symmetric (for all i and for all j M[i][j] = M[j][i])
  - all off-diagonal elements must be positive (i!=j)

  In physics, the center of mass for a distribution of masses in the space is the unique point where
  the weighted relative position of the distributed mass sums to zero. Here, the sum of vectors to
  all nodes from the center of mass is zero (All the nodes being the unit of mass)

  The distance between center of mass and each node is then reduced to this formula using law of cosine
  and center of mass:
  `$$ dic^2 =  {1\over n} \sum_{j=1}^{n} dij^2 - {1\over n^2}\sum_{j=2}^{n}\sum_{k=1}^{j-1} djk^2 $$`

  Then using the laws of Cosine, we can compute a gram matrix which would help to plot the nodes in a 2D plan:
  `$$ gij =  {1\over 2} (dic^2 + djc^2 - dij^2) $$`

  Finally, because the nodes are in a 2D plan, we can factorize the gram matrix to get the eigenvalues and
  eigenvectors to find their corresponding coordinates

  ### Examples

      iex> NetworkCoordinates.get_patch_from_latencies(Nx.tensor([
      ...>  [0, 100, 150],
      ...>  [100, 0, 200],
      ...>  [150, 200, 0]
      ...> ], names: [:line, :column], type: {:f, 64}))
      [
        "B8",
        "08",
        "C8"
      ]
  """
  @spec get_patch_from_latencies(Nx.Tensor.t()) :: list(String.t())
  def get_patch_from_latencies(matrix) do
    formated_matrix =
      matrix
      |> Nx.as_type(:f64)
      |> Nx.rename([:line, :column])

    center_mass = compute_distance_from_center_mass(formated_matrix)
    gram_matrix = get_gram_matrix(formated_matrix, center_mass)
    {x, y} = get_coordinates(gram_matrix)
    get_patch_digits(x, y)
  end

  defp compute_distance_from_center_mass(tensor) do
    matrix_size = Nx.size(tensor[0])

    a =
      tensor
      |> Nx.pow(2)
      |> Nx.sum(axes: [:column])
      |> Nx.multiply(Nx.tensor(1.0 / matrix_size, type: {:f, 64}))

    excluded_first_row_tensor = tensor[1..-1//1]

    b =
      1..(matrix_size - 1)
      |> Enum.map(fn i ->
        excluded_first_row_tensor
        |> Nx.slice([i - 1, 0], [1, i])
        |> Nx.pow(2)
        |> Nx.sum()
      end)
      |> Nx.stack()
      |> Nx.sum()
      |> Nx.to_number()

    b_prime = Nx.tensor(1.0 / (matrix_size * matrix_size) * b, type: {:f, 64})

    Nx.subtract(a, b_prime)
  end

  defp get_gram_matrix(matrix_tensor, center_mass_tensor) do
    matrix_size = Nx.size(center_mass_tensor)

    Enum.map(0..(matrix_size - 1), fn i ->
      dic = center_mass_tensor[i]

      Enum.map(0..(matrix_size - 1), fn j ->
        djc = center_mass_tensor[j]
        dij = matrix_tensor[i][j]

        dic
        |> Nx.pow(2)
        |> Nx.add(Nx.pow(djc, 2))
        |> Nx.subtract(Nx.pow(dij, 2))
        |> Nx.multiply(Nx.tensor(0.5, type: {:f, 64}))
      end)
      |> Nx.stack()
    end)
    |> Nx.stack()
  end

  defp get_coordinates(gram_matrix) do
    matrix_size = Nx.size(gram_matrix[0])
    {eigen_values, eigen_vectors} = Nx.LinAlg.eigh(gram_matrix)

    [{e1, i1}, {e2, i2}] =
      eigen_values
      |> Nx.to_flat_list()
      |> Enum.with_index()
      |> Enum.sort_by(fn {i, _} -> i end, :desc)
      |> Enum.take(2)

    eigen_value1 = e1 |> Nx.sqrt()
    eigen_value2 = e2 |> Nx.sqrt()

    eigen_vector1 = eigen_vectors[i1]
    eigen_vector2 = eigen_vectors[i2]

    %{x: x, y: y} =
      Enum.reduce(
        0..(matrix_size - 1),
        %{x: Nx.broadcast(0, {matrix_size}), y: Nx.broadcast(0, {matrix_size})},
        fn i, acc ->
          acc
          |> Map.update!(:x, fn x ->
            Nx.indexed_add(
              x,
              Nx.tensor([[i]]),
              Nx.multiply(eigen_vector1[i], eigen_value1) |> Nx.reshape({1})
            )
          end)
          |> Map.update!(:y, fn y ->
            Nx.indexed_add(
              y,
              Nx.tensor([[i]]),
              Nx.multiply(eigen_vector2[i], eigen_value2) |> Nx.reshape({1})
            )
          end)
        end
      )

    {x, y}
  end

  defp get_patch_digits(x, y) do
    max = Nx.max(Nx.abs(x), Nx.abs(y)) |> Nx.to_flat_list() |> Enum.max()

    v = 2.0 * max / 16.0

    x_size = Nx.size(x)

    Enum.map(0..(x_size - 1), fn i ->
      x_elem = x[i] |> Nx.to_number()
      y_elem = y[i] |> Nx.to_number()

      get_patch(x_elem, y_elem, v, max)
    end)
  end

  defp get_patch(x_elem, y_elem, v, max) do
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

    "#{x}#{y}"
  end

  defp get_digit(acc, coord_name, coord, digit_index, max, v)
       when coord >= max - v * (digit_index + 1.0) and coord <= max - v * digit_index do
    Map.put(acc, coord_name, Enum.at(@digits, digit_index))
  end

  defp get_digit(acc, _, _, _, _, _), do: acc

  @doc """
  Fetch remotely the network stats for a given summary time  

  This request all the subsets to gather the aggregated network stats.
  A NxN latency matrix is then computed based on the network stats origins and targets
  """
  @spec fetch_network_stats(DateTime.t()) :: Nx.Tensor.t()
  def fetch_network_stats(summary_time = %DateTime{}) do
    authorized_nodes = P2P.authorized_and_available_nodes()

    sorted_node_list = P2P.list_nodes() |> Enum.sort_by(& &1.first_public_key)
    nb_nodes = length(sorted_node_list)

    matrix = Nx.broadcast(0, {nb_nodes, nb_nodes})

    %{bounded: bounded_subsets, unbounded: unbounded_subsets} =
      get_subsets_bounding(summary_time, authorized_nodes)

    bounded_netstats =
      bounded_subsets
      |> Task.async_stream(&{&1, aggregate_network_stats(&1)})
      |> Enum.reduce(%{}, fn
        {:ok, {subset, stats}}, acc when map_size(stats) > 0 ->
          Map.put(acc, subset, stats)

        _, acc ->
          acc
      end)

    unbounded_matrix =
      unbounded_subsets
      # Aggregate subsets by node
      |> Enum.reduce(%{}, fn {subset, beacon_nodes}, acc ->
        Enum.reduce(beacon_nodes, acc, fn node, acc ->
          Map.update(acc, node, [subset], &[subset | &1])
        end)
      end)
      |> stream_subsets_stats()
      # Aggregate stats per node to identify the sampling nodes
      |> aggregate_stats_per_subset()
      |> update_matrix_from_stats(matrix, sorted_node_list)

    full_matrix = update_matrix_from_stats(bounded_netstats, unbounded_matrix, sorted_node_list)
    full_matrix
  end

  defp get_subsets_bounding(summary_time, authorized_nodes) do
    Enum.reduce(BeaconChain.list_subsets(), %{bounded: [], unbounded: []}, fn subset, acc ->
      beacon_nodes = Election.beacon_storage_nodes(subset, summary_time, authorized_nodes)

      if Utils.key_in_node_list?(beacon_nodes, Crypto.first_node_public_key()) do
        Map.update!(acc, :bounded, &[subset | &1])
      else
        Map.update!(acc, :unbounded, &[{subset, beacon_nodes} | &1])
      end
    end)
  end

  defp stream_subsets_stats(subsets_by_node) do
    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      subsets_by_node,
      fn {node, subsets} ->
        P2P.send_message(node, %GetNetworkStats{subsets: subsets})
      end,
      ordered: false,
      on_timeout: :kill_task,
      max_concurrency: 256
    )
    |> Stream.filter(fn
      {:ok, {:ok, %NetworkStats{stats: stats}}} when map_size(stats) > 0 ->
        true

      _ ->
        false
    end)
    |> Stream.map(fn {:ok, {:ok, %NetworkStats{stats: stats}}} -> stats end)
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
          aggregated_stats =
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

          Map.put(acc, node, aggregated_stats)
        end)

      Map.put(acc, subset, aggregated_stats_by_node)
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
  @spec aggregate_network_stats(binary()) :: %{Crypto.key() => Slot.net_stats()}
  def aggregate_network_stats(subset) when is_binary(subset) do
    subset
    |> SummaryCache.stream_current_slots()
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
