defmodule Archethic.P2P.Message.ListNodes do
  @moduledoc """
  Represents a message to fetch the list of nodes
  """
  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Message.NodeList

  defstruct []

  @type t :: %__MODULE__{}

  @spec process(__MODULE__.t(), Crypto.key()) :: NodeList.t()
  def process(%__MODULE__{}, _) do
    %NodeList{nodes: P2P.list_nodes()}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{}), do: <<>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>),
    do: {
      %__MODULE__{},
      rest
    }
end
