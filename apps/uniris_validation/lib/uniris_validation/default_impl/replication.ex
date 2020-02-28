defmodule UnirisValidation.DefaultImpl.Replication do
  @moduledoc false

  alias UnirisValidation.DefaultImpl.BinarySequence

  @doc ~S"""
  Define a tree from a list of storage nodes and validation nodes by grouping
  closest closest nodes by the shorter path.

  # Examples

    Given a list of storage nodes: S1, S2, .., S16 and list of validation nodes: V1, .., V5

    Nodes coordinates (Network Patch ID : numerical value)

     S1: F36 -> 3894  S5: 143 -> 323   S9: 19A -> 410    S13: E2B -> 3627
     S2: A23 -> 2595  S6: BB2 -> 2994  S10: C2A -> 3114  S14: AA0 -> 2720
     S3: B43 -> 2883  S7: A63 -> 2659  S11: C23 -> 3107  S15: 042 -> 66
     S4: 2A9 -> 681   S8: D32 -> 3378  S12: F22 -> 3874  S16: 3BC -> 956

     V1: AC2 -> 2754  V2: DF3 -> 3571  V3: C22 -> 3106  V4: E19 -> 3609  V5: 22A -> 554

    The replication tree is computed by find the nearest storages nodes for each validations

    Foreach storage nodes its distance is computed with each validation nodes and then sorted to the get the closest.

    Table below shows the distance between storages and validations

      |------------|------------|------------|------------|------------|------------|-------------|------------|
      | S1         | S2         | S3         | S4         | S5         | S6         | S7          | S8         |
      |------------|------------|------------|------------|------------|------------|-------------|------------|
      |  V1 , 1140 |  V1 , 159  |  V1 , 129  |  V1 , 2073 |  V1 , 2431 |  V1 , 240  |  V1 , 95    |  V1 , 624  |
      |  V2 , 323  |  V2 , 976  |  V2 , 688  |  V2 , 2890 |  V2 , 3248 |  V2 , 577  |  V2 , 912   |  V2 , 193  |
      |  V3 , 788  |  V3 , 511  |  V3 , 223  |  V3 , 2425 |  V3 , 2783 |  V3 , 112  |  V3 , 447   |  V3 , 272  |
      |  V4 , 285  |  V4 , 1014 |  V4 , 726  |  V4 , 2928 |  V4 , 3286 |  V4 , 615  |  V4 , 950   |  V4 , 231  |
      |  V5 , 3340 |  V5 , 2041 |  V5 , 2329 |  V5 , 127  |  V5 , 231  |  V5 , 2440 |  V5 , 2105  |  V5 , 2824 |
      |------------|------------|------------|------------|------------|------------|-------------|------------|
      | S9         | S10        | S11        | S12        | S13        | S14        | S15         | S16        |
      |------------|------------|------------|------------|------------|------------|-------------|------------|
      |  V1 , 2344 |  V1 , 360  |  V1 , 353  |  V1 , 1120 |  V1 , 873  |  V1 , 34   |  V1 , 2688  |  V1 , 1798 |
      |  V2 , 3161 |  V2 , 457  |  V2 , 464  |  V2 , 303  |  V2 , 56   |  V2 , 851  |  V2 , 3505  |  V2 , 2615 |
      |  V3 , 2696 |  V3 , 8    |  V3 , 1    |  V3 , 768  |  V3 , 521  |  V3 , 386  |  V3 , 3040  |  V3 , 2150 |
      |  V4 , 3199 |  V4 , 495  |  V4 , 502  |  V4 , 265  |  V4 , 18   |  V4 , 889  |  V4 , 3543  |  V4 , 2653 |
      |  V5 , 144  |  V5 , 2560 |  V5 , 2553 |  V5 , 3320 |  V5 , 3078 |  V5 , 2166 |  V5 , 488   |  V5 , 402  |

    By sorting them we can reverse and to find the closest storages nodes.
    Table below shows the storages nodes by validation nodes

       |-----|-----|-----|-----|-----|
       | V1  | V2  | V3  | V4  | V5  |
       |-----|-----|-----|-----|-----|
       | S2  | S8  | S6  | S1  | S4  |
       | S3  |     | S10 | S13 | S5  |
       | S7  |     | S11 | S12 | S9  |
       | S14 |     |     |     | S15 |
       |     |     |     |     | S16 |


     iex> validation_nodes = [
     ...> %{network_patch: "AC2", last_public_key: "key_v1"},
     ...> %{network_patch: "DF3", last_public_key: "key_v2"},
     ...> %{network_patch: "C22", last_public_key: "key_v3"},
     ...> %{network_patch: "E19", last_public_key: "key_v4"},
     ...> %{network_patch: "22A", last_public_key: "key_v5"}
     ...> ]
     iex> storage_nodes = [
     ...> %{network_patch: "F36", first_public_key: "key_S1", last_public_key: "key_S1"},
     ...> %{network_patch: "A23", first_public_key: "key_S2", last_public_key: "key_S2"},
     ...> %{network_patch: "B43", first_public_key: "key_S3", last_public_key: "key_S3"},
     ...> %{network_patch: "2A9", first_public_key: "key_S4", last_public_key: "key_S4"},
     ...> %{network_patch: "143", first_public_key: "key_S5", last_public_key: "key_S5"},
     ...> %{network_patch: "BB2", first_public_key: "key_S6", last_public_key: "key_S6"},
     ...> %{network_patch: "A63", first_public_key: "key_S7", last_public_key: "key_S7"},
     ...> %{network_patch: "D32", first_public_key: "key_S8", last_public_key: "key_S8"},
     ...> %{network_patch: "19A", first_public_key: "key_S9", last_public_key: "key_S9"},
     ...> %{network_patch: "C2A", first_public_key: "key_S10", last_public_key: "key_S10"},
     ...> %{network_patch: "C23", first_public_key: "key_S11", last_public_key: "key_S11"},
     ...> %{network_patch: "F22", first_public_key: "key_S12", last_public_key: "key_S12"},
     ...> %{network_patch: "E2B", first_public_key: "key_S13", last_public_key: "key_S13"},
     ...> %{network_patch: "AA0", first_public_key: "key_S14", last_public_key: "key_S14"},
     ...> %{network_patch: "042", first_public_key: "key_S15", last_public_key: "key_S15"},
     ...> %{network_patch: "3BC", first_public_key: "key_S16", last_public_key: "key_S16"}
     ...> ]
     iex> UnirisValidation.DefaultImpl.Replication.build_tree(validation_nodes, storage_nodes)
     %{
       "key_v1" => [
         %{network_patch: "A23", first_public_key: "key_S2", last_public_key: "key_S2"},
         %{network_patch: "B43", first_public_key: "key_S3", last_public_key: "key_S3"},
         %{network_patch: "A63", first_public_key: "key_S7", last_public_key: "key_S7"},
         %{network_patch: "AA0", first_public_key: "key_S14", last_public_key: "key_S14"}
       ],               
       "key_v2" => [    
         %{network_patch: "D32", first_public_key: "key_S8", last_public_key: "key_S8"}
       ],               
       "key_v3" => [    
         %{network_patch: "BB2", first_public_key: "key_S6", last_public_key: "key_S6"},
         %{network_patch: "C2A", first_public_key: "key_S10", last_public_key: "key_S10"},
         %{network_patch: "C23", first_public_key: "key_S11", last_public_key: "key_S11"}
       ],               
       "key_v4" => [    
         %{network_patch: "F36", first_public_key: "key_S1", last_public_key: "key_S1"},
         %{network_patch: "F22", first_public_key: "key_S12", last_public_key: "key_S12"},
         %{network_patch: "E2B", first_public_key: "key_S13", last_public_key: "key_S13"}
       ],               
       "key_v5" => [    
         %{network_patch: "2A9", first_public_key: "key_S4", last_public_key: "key_S4"},
         %{network_patch: "143", first_public_key: "key_S5", last_public_key: "key_S5"},
         %{network_patch: "19A", first_public_key: "key_S9", last_public_key: "key_S9"},
         %{network_patch: "042", first_public_key: "key_S15", last_public_key: "key_S15"},
         %{network_patch: "3BC", first_public_key: "key_S16", last_public_key: "key_S16"}
       ]
     }
  """
  def build_tree(validation_nodes, storage_nodes) do
    storage_nodes
    |> Enum.reduce(%{}, fn storage_node, acc ->
      storage_node_weight =
        storage_node.network_patch |> String.to_charlist() |> List.to_integer(16)

      [closest_validation_node] =
        Enum.sort_by(validation_nodes, fn validation_node ->
          validation_node_weight =
            validation_node.network_patch |> String.to_charlist() |> List.to_integer(16)

          abs(storage_node_weight - validation_node_weight)
        end)
        |> Enum.take(1)

      Map.update(
        acc,
        closest_validation_node.last_public_key,
        [storage_node],
        &(&1 ++ [storage_node])
      )
    end)
  end

  @doc """
  Generate the replication as `UnirisValidation.Replication.build_tree/2` but output as binary sequence from the storage node list

  It helps to reduce the size of the data since each subset from each validation nodes will contains the length of storage nodes list as bits.

  ## Examples

     iex> validation_nodes = [
     ...> %{network_patch: "AC2", last_public_key: "key_v1"},
     ...> %{network_patch: "DF3", last_public_key: "key_v2"},
     ...> %{network_patch: "C22", last_public_key: "key_v3"},
     ...> %{network_patch: "E19", last_public_key: "key_v4"},
     ...> %{network_patch: "22A", last_public_key: "key_v5"}
     ...> ]
     iex> storage_nodes = [
     ...> %{network_patch: "F36", first_public_key: "key_S1", last_public_key: "key_S1"},
     ...> %{network_patch: "A23", first_public_key: "key_S2", last_public_key: "key_S2"},
     ...> %{network_patch: "B43", first_public_key: "key_S3", last_public_key: "key_S3"},
     ...> %{network_patch: "2A9", first_public_key: "key_S4", last_public_key: "key_S4"},
     ...> %{network_patch: "143", first_public_key: "key_S5", last_public_key: "key_S5"},
     ...> %{network_patch: "BB2", first_public_key: "key_S6", last_public_key: "key_S6"},
     ...> %{network_patch: "A63", first_public_key: "key_S7", last_public_key: "key_S7"},
     ...> %{network_patch: "D32", first_public_key: "key_S8", last_public_key: "key_S8"},
     ...> %{network_patch: "19A", first_public_key: "key_S9", last_public_key: "key_S9"},
     ...> %{network_patch: "C2A", first_public_key: "key_S10", last_public_key: "key_S10"},
     ...> %{network_patch: "C23", first_public_key: "key_S11", last_public_key: "key_S11"},
     ...> %{network_patch: "F22", first_public_key: "key_S12", last_public_key: "key_S12"},
     ...> %{network_patch: "E2B", first_public_key: "key_S13", last_public_key: "key_S13"},
     ...> %{network_patch: "AA0", first_public_key: "key_S14", last_public_key: "key_S14"},
     ...> %{network_patch: "042", first_public_key: "key_S15", last_public_key: "key_S15"},
     ...> %{network_patch: "3BC", first_public_key: "key_S16", last_public_key: "key_S16"}
     ...> ]
     iex> tree = UnirisValidation.DefaultImpl.Replication.build_binary_tree(validation_nodes, storage_nodes)
     iex> Enum.map(tree, &(UnirisValidation.DefaultImpl.BinarySequence.extract(&1)))
     [
       [0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0],
       [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0],
       [0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0],
       [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0],
       [0, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1]
     ]
     iex> Enum.all?(tree, &bit_size(&1) == 16)
     true
  """
  def build_binary_tree(validation_nodes, storage_nodes) do
    build_tree(validation_nodes, storage_nodes)
    |> Enum.map(fn {_, list} ->
      BinarySequence.from_subset(storage_nodes, list)
    end)
  end
end
