defmodule Archethic.P2P.Message.P2PView do
  @moduledoc """
  Represents a P2P view from a list of nodes as bit sequence
  """
  defstruct [:nodes_view]

  @type t :: %__MODULE__{
          nodes_view: bitstring()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{nodes_view: view}) do
    <<bit_size(view)::8, view::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<view_size::8, rest::bitstring>>) do
    <<nodes_view::bitstring-size(view_size), rest::bitstring>> = rest
    {%__MODULE__{nodes_view: nodes_view}, rest}
  end
end
