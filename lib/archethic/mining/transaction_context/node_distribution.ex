defmodule Archethic.Mining.TransactionContext.NodeDistribution do
  @moduledoc false

  @doc """
  Split the previous storage nodes into groups to distribute fairly
  the storage nodes involved, avoiding nodes overlapping if possible

  ## Examples

      iex> NodeDistribution.split_storage_nodes(
      ...>   [
      ...>     %Node{first_public_key: "key1"},
      ...>     %Node{first_public_key: "key2"},
      ...>     %Node{first_public_key: "key3"},
      ...>     %Node{first_public_key: "key4"},
      ...>     %Node{first_public_key: "key5"},
      ...>     %Node{first_public_key: "key6"},
      ...>     %Node{first_public_key: "key7"},
      ...>     %Node{first_public_key: "key8"},
      ...>     %Node{first_public_key: "key9"}
      ...>   ],
      ...>   3,
      ...>   3
      ...> )
      [
        [
          %Node{first_public_key: "key1"},
          %Node{first_public_key: "key4"},
          %Node{first_public_key: "key7"}
        ],
        [
          %Node{first_public_key: "key2"},
          %Node{first_public_key: "key5"},
          %Node{first_public_key: "key8"}
        ],
        [
          %Node{first_public_key: "key3"},
          %Node{first_public_key: "key6"},
          %Node{first_public_key: "key9"}
        ]
      ]

    Distribute across sublist if the number of nodes doesn't match the number of sub lists and sample size

      iex> NodeDistribution.split_storage_nodes(
      ...>   [
      ...>     %Node{first_public_key: "key1"},
      ...>     %Node{first_public_key: "key2"},
      ...>     %Node{first_public_key: "key3"},
      ...>     %Node{first_public_key: "key4"}
      ...>   ],
      ...>   3,
      ...>   3
      ...> )
      [
        [
          %Node{first_public_key: "key1"},
          %Node{first_public_key: "key4"},
          %Node{first_public_key: "key3"},
          %Node{first_public_key: "key2"}
        ],
        [
          %Node{first_public_key: "key2"},
          %Node{first_public_key: "key1"},
          %Node{first_public_key: "key4"},
          %Node{first_public_key: "key3"}
        ],
        [
          %Node{first_public_key: "key3"},
          %Node{first_public_key: "key2"},
          %Node{first_public_key: "key1"},
          %Node{first_public_key: "key4"}
        ]
      ]

      iex> NodeDistribution.split_storage_nodes(
      ...>   [
      ...>     %Node{first_public_key: "key1"},
      ...>     %Node{first_public_key: "key2"},
      ...>     %Node{first_public_key: "key3"},
      ...>     %Node{first_public_key: "key4"}
      ...>   ],
      ...>   2,
      ...>   3
      ...> )
      [
        [%Node{first_public_key: "key1"}, %Node{first_public_key: "key3"}],
        [%Node{first_public_key: "key2"}, %Node{first_public_key: "key4"}]
      ]

      iex> NodeDistribution.split_storage_nodes(
      ...>   [
      ...>     %Node{first_public_key: "key1"},
      ...>     %Node{first_public_key: "key2"},
      ...>     %Node{first_public_key: "key3"},
      ...>     %Node{first_public_key: "key4"}
      ...>   ],
      ...>   5,
      ...>   3
      ...> )
      [
        [
          %Node{first_public_key: "key1"},
          %Node{first_public_key: "key2"},
          %Node{first_public_key: "key3"},
          %Node{first_public_key: "key4"}
        ],
        [
          %Node{first_public_key: "key2"},
          %Node{first_public_key: "key3"},
          %Node{first_public_key: "key4"}
        ],
        [
          %Node{first_public_key: "key3"},
          %Node{first_public_key: "key4"},
          %Node{first_public_key: "key1"}
        ],
        [
          %Node{first_public_key: "key4"},
          %Node{first_public_key: "key1"},
          %Node{first_public_key: "key2"}
        ],
        [
          %Node{first_public_key: "key1"},
          %Node{first_public_key: "key2"},
          %Node{first_public_key: "key3"}
        ]
      ]

  """
  @spec split_storage_nodes(
          storage_nodes :: list(Node.t()),
          nb_sub_list :: pos_integer(),
          sample_size :: pos_integer()
        ) :: list(list(Node.t()))

  def split_storage_nodes(storage_nodes, nb_sublist, sample_size)
      when is_list(storage_nodes) and is_number(nb_sublist) and nb_sublist > 0 and
             is_number(sample_size) and sample_size > 0 do
    do_split(storage_nodes, nb_sublist, sample_size, Enum.map(1..nb_sublist, fn _ -> [] end))
  end

  defp do_split(storage_nodes, nb_sublist, sample_size, sub_lists) do
    split =
      storage_nodes
      |> Enum.reduce(sub_lists, fn node, acc ->
        smallest_sub_list = Enum.min_by(acc, &length/1)
        sub_list_index_to_add = Enum.find_index(acc, &(&1 == smallest_sub_list))
        List.update_at(acc, sub_list_index_to_add, &[node | &1])
      end)

    if Enum.all?(split, &(length(&1) >= sample_size)) do
      Enum.map(split, fn list ->
        list
        |> Enum.reverse()
        |> Enum.uniq_by(& &1.first_public_key)
      end)
    else
      do_split(storage_nodes, nb_sublist, sample_size, split)
    end
  end
end
