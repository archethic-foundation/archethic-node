defmodule Archethic.P2P.Message.ListNodes do
  @moduledoc """
  Represents a message to fetch the list of nodes
  """
  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.NodeList

  defstruct [:authorized_and_available?]

  @type t :: %__MODULE__{
          authorized_and_available?: boolean()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: NodeList.t()
  def process(%__MODULE__{authorized_and_available?: false}, _),
    do: %NodeList{nodes: P2P.list_nodes()}

  def process(%__MODULE__{authorized_and_available?: true}, _),
    do: %NodeList{nodes: P2P.authorized_and_available_nodes()}

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{authorized_and_available?: false}), do: <<0::8>>
  def serialize(%__MODULE__{authorized_and_available?: true}), do: <<1::8>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<0::8, rest::bitstring>>),
    do: {%__MODULE__{authorized_and_available?: false}, rest}

  def deserialize(<<1::8, rest::bitstring>>),
    do: {%__MODULE__{authorized_and_available?: true}, rest}
end
