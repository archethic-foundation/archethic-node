defmodule ArchEthic.P2P.Message.ListNodes do
  @moduledoc """
  Represents a message to fetch the list of nodes
  """
  defstruct []

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.NodeList

  use ArchEthic.P2P.Message, message_id: 2

  @type t :: %__MODULE__{}

  def encode(%__MODULE__{}) do
    <<>>
  end

  def decode(rest) when is_bitstring(rest) do
    rest
  end

  def process(%__MODULE__{}) do
    %NodeList{
      nodes: P2P.list_nodes()
    }
  end
end
