defmodule ArchEthic.P2P.Message.GetBootstrappingNodes do
  @moduledoc """
  Represents a message to list the new bootstrapping nodes for a network patch.
  The closest authorized nodes will be returned.

  This message is used during the node bootstrapping.
  """
  @enforce_keys [:patch]
  defstruct [:patch]

  @type t() :: %__MODULE__{
          patch: binary()
        }

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.BootstrappingNodes

  use ArchEthic.P2P.Message, message_id: 0

  def encode(%__MODULE__{patch: patch}) do
    patch
  end

  def decode(<<patch::binary-size(3), rest::bitstring>>) do
    {%__MODULE__{patch: patch}, rest}
  end

  def process(%__MODULE__{patch: patch}) do
    top_nodes = P2P.authorized_nodes()

    closest_nodes =
      top_nodes
      |> P2P.nearest_nodes(patch)
      |> Enum.take(5)

    %BootstrappingNodes{
      new_seeds: Enum.take_random(top_nodes, 5),
      closest_nodes: closest_nodes
    }
  end
end
