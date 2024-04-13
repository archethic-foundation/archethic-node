defmodule Archethic.P2P.Message.GetBootstrappingNodes do
  @moduledoc """
  Represents a message to list the new bootstrapping nodes for a network patch.
  The closest authorized nodes will be returned.

  This message is used during the node bootstrapping.
  """

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.BootstrappingNodes

  @enforce_keys [:patch]
  defstruct [:patch]

  @type t() :: %__MODULE__{
          patch: binary()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: BootstrappingNodes.t()
  def process(%__MODULE__{patch: patch}, _) do
    top_nodes = P2P.authorized_and_available_nodes()

    closest_nodes =
      top_nodes
      |> P2P.nearest_nodes(patch)
      |> Enum.take(5)

    %BootstrappingNodes{
      new_seeds: Enum.take_random(top_nodes, 5),
      closest_nodes: closest_nodes,
      first_enrolled_node: P2P.get_first_enrolled_node()
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{patch: patch}) do
    <<patch::binary-size(3)>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<patch::binary-size(3), rest::bitstring>>) do
    {
      %__MODULE__{patch: patch},
      rest
    }
  end
end
