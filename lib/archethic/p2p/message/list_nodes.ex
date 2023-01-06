defmodule Archethic.P2P.Message.ListNodes do
  @moduledoc """
  Represents a message to fetch the list of nodes
  """
  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Message.NodeList

  defstruct []

  @type t :: %__MODULE__{}

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{}) do
    <<2::8>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: NodeList.t()
  def process(%__MODULE__{}, _) do
    %NodeList{nodes: P2P.list_nodes()}
  end
end
