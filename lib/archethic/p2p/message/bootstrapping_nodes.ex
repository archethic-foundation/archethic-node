defmodule ArchEthic.P2P.Message.BootstrappingNodes do
  @moduledoc """
  Represents a message with the list of closest bootstrapping nodes.

  This message is used during the node bootstrapping
  """
  defstruct new_seeds: [], closest_nodes: []

  alias ArchEthic.P2P.Node
  alias ArchEthic.Utils

  @type t() :: %__MODULE__{
          new_seeds: list(Node.t()),
          closest_nodes: list(Node.t())
        }

  use ArchEthic.P2P.Message, message_id: 246

  def encode(%__MODULE__{new_seeds: new_seeds, closest_nodes: closest_nodes}) do
    new_seeds_bin =
      new_seeds
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    closest_nodes_bin =
      closest_nodes
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    <<length(new_seeds)::8, new_seeds_bin::bitstring, length(closest_nodes)::8,
      closest_nodes_bin::bitstring>>
  end

  def decode(<<nb_new_seeds::8, rest::bitstring>>) do
    {new_seeds, <<nb_closest_nodes::8, rest::bitstring>>} =
      Utils.deserialize_node_list(rest, nb_new_seeds, [])

    {closest_nodes, rest} = Utils.deserialize_node_list(rest, nb_closest_nodes, [])

    {%__MODULE__{
       new_seeds: new_seeds,
       closest_nodes: closest_nodes
     }, rest}
  end

  def process(%__MODULE__{}) do
  end
end
