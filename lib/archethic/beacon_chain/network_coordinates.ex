defmodule Archethic.BeaconChain.NetworkCoordinates do
  @moduledoc """
  Network coordinates is a way to map latency between nodes and used to determine the closest nodes
  """

  @digits ["F", "E", "D", "C", "B", "A", "9", "8", "7", "6", "5", "4", "3", "2", "1", "0"]

  @type latency_patch :: {String.t(), String.t()}

  @doc """
  Compute the network patch based on the matrix latencies

  The matrix must be an Hollow matrix, symmetric and all the latencies must be positive

  In physicis, the center of mass of a distribution of mass in the space is the unique point where
  the weighted relative position of the distributed mass sums to zero. Here, the sum of vectors to
  all nodes from the center of mass is zero (All the nodes being the unit of mass)

  The distance between center of mass and each node is then reduced to this formula using law of cosine
  and center of mass:
  `$$ dic^2 =  {1\over 2} \sum_{j=1}^{n} dij^2 - {1\over 2}\sum_{j=2}^{n}\sum_{k=1}^{j-1} djk^2 $$`

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
        {"B", "8"},
        {"0", "8"},
        {"C", "8"}
      ]
  """
  @spec get_patch_from_latencies(Nx.tensor()) :: list(latency_patch())
  def get_patch_from_latencies(matrix) do
    center_mass = compute_distance_from_center_mass(matrix)
    gram_matrix = get_gram_matrix(matrix, center_mass)
    {x, y} = get_coordinates(gram_matrix)
    get_patch_digits(x, y)
  end

  # defp get_matrix_tensor() do
  #  "distance_matrix.dat"
  #  |> File.read!
  #  |> String.split("\n", trim: true)
  #  |> Enum.map(fn line ->
  #    line
  #    |> String.split(",", trim: true)
  #    |> Enum.map(&String.to_float/1)
  #  end)
  #  |> Nx.tensor(names: [:line, :column], type: {:f, 64})
  # end

  defp compute_distance_from_center_mass(tensor) do
    matrix_size = Nx.size(tensor[0])

    a =
      tensor
      |> Nx.power(2)
      |> Nx.sum(axes: [:column])
      |> Nx.multiply(Nx.tensor(1.0 / matrix_size, type: {:f, 64}))

    excluded_first_row_tensor = tensor[1..-1//1]

    b =
      1..(matrix_size - 1)
      |> Enum.map(fn i ->
        excluded_first_row_tensor
        |> Nx.slice([i - 1, 0], [1, i])
        |> Nx.power(2)
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
        |> Nx.power(2)
        |> Nx.add(Nx.power(djc, 2))
        |> Nx.subtract(Nx.power(dij, 2))
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

      %{fd: fd, sd: sd} =
        Enum.reduce_while(0..15, %{fd: "", sd: ""}, fn j, acc ->
          if acc.fd != "" and acc.sd != "" do
            {:halt, acc}
          else
            acc =
              if x_elem >= max - v * (j + 1.0) and x_elem <= max - v * j do
                Map.put(acc, :fd, Enum.at(@digits, j))
              else
                acc
              end

            acc =
              if y_elem >= max - v * (j + 1.0) and y_elem <= max - v * j do
                Map.put(acc, :sd, Enum.at(@digits, j))
              else
                acc
              end

            {:cont, acc}
          end
        end)

      {fd, sd}
    end)
  end
end
