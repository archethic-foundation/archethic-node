defmodule Archethic.P2P.Message.BootstrappingNodes do
  @moduledoc """
  Represents a message with the list of closest bootstrapping nodes.

  This message is used during the node bootstrapping
  """
  defstruct new_seeds: [], closest_nodes: []

  alias Archethic.P2P.Node
  alias Archethic.Utils.VarInt

  @type t() :: %__MODULE__{
          new_seeds: list(Node.t()),
          closest_nodes: list(Node.t())
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{new_seeds: new_seeds, closest_nodes: closest_nodes}) do
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

    <<246::8, encoded_new_seeds_length::binary, new_seeds_bin::bitstring,
      encoded_closest_nodes_length::binary, closest_nodes_bin::bitstring>>
  end
end
