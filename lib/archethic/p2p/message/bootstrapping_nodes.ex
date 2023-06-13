defmodule Archethic.P2P.Message.BootstrappingNodes do
  @moduledoc """
  Represents a message with the list of closest bootstrapping nodes.

  This message is used during the node bootstrapping
  """
  defstruct [:first_enrolled_node, new_seeds: [], closest_nodes: []]

  alias Archethic.P2P.Node
  alias Archethic.Utils.VarInt

  @type t() :: %__MODULE__{
          new_seeds: list(Node.t()),
          closest_nodes: list(Node.t()),
          first_enrolled_node: Node.t()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        new_seeds: new_seeds,
        closest_nodes: closest_nodes,
        first_enrolled_node: first_enrolled_node
      }) do
    new_seeds_bin =
      new_seeds
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    closest_nodes_bin =
      closest_nodes
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_new_seeds_length = length(new_seeds) |> VarInt.from_value()

    encoded_closest_nodes_length = length(closest_nodes) |> VarInt.from_value()

    first_enrolled_node_bin = Node.serialize(first_enrolled_node)

    <<encoded_new_seeds_length::binary, new_seeds_bin::bitstring,
      encoded_closest_nodes_length::binary, closest_nodes_bin::bitstring,
      first_enrolled_node_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_new_seeds, rest} = rest |> VarInt.get_value()
    {new_seeds, <<rest::bitstring>>} = deserialize_node_list(rest, nb_new_seeds, [])

    {nb_closest_nodes, rest} = rest |> VarInt.get_value()
    {closest_nodes, rest} = deserialize_node_list(rest, nb_closest_nodes, [])

    {first_enrolled_node, rest} = Node.deserialize(rest)

    {%__MODULE__{
       new_seeds: new_seeds,
       closest_nodes: closest_nodes,
       first_enrolled_node: first_enrolled_node
     }, rest}
  end

  defp deserialize_node_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_node_list(rest, nb_nodes, acc) when length(acc) == nb_nodes do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_node_list(rest, nb_nodes, acc) do
    {node, rest} = Node.deserialize(rest)
    deserialize_node_list(rest, nb_nodes, [node | acc])
  end
end
