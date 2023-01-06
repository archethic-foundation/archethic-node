defmodule Archethic.P2P.Message.GetP2PView do
  @moduledoc """
  Represents a request to get the P2P view from a list of nodes
  """
  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Message.P2PView

  defstruct [:node_public_keys]

  @type t :: %__MODULE__{
          node_public_keys: list(Crypto.key())
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: P2PView.t()
  def process(%__MODULE__{node_public_keys: node_public_keys}, _) do
    nodes =
      Enum.map(node_public_keys, fn key ->
        {:ok, node} = P2P.get_node_info(key)
        node
      end)

    view = P2P.nodes_availability_as_bits(nodes)
    %P2PView{nodes_view: view}
  end
end
