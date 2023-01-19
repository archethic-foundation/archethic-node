defmodule Archethic.P2P.Message.NodeList do
  @moduledoc """
  Represents a message a list of nodes
  """
  defstruct nodes: []

  alias Archethic.P2P.Node
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          nodes: list(Node.t())
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{nodes: nodes}) do
    nodes_bin =
      nodes
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_nodes_length = length(nodes) |> VarInt.from_value()

    <<encoded_nodes_length::binary, nodes_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_nodes, rest} = rest |> VarInt.get_value()
    {nodes, rest} = deserialize_node_list(rest, nb_nodes, [])
    {%__MODULE__{nodes: nodes}, rest}
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
