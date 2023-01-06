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

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{nodes: nodes}) do
    nodes_bin =
      nodes
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_nodes_length = length(nodes) |> VarInt.from_value()

    <<249::8, encoded_nodes_length::binary, nodes_bin::bitstring>>
  end
end
