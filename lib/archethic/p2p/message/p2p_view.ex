defmodule Archethic.P2P.Message.P2PView do
  @moduledoc """
  Represents a P2P view from a list of nodes as bit sequence
  """
  defstruct [:nodes_view]

  @type t :: %__MODULE__{
          nodes_view: bitstring()
        }
end
