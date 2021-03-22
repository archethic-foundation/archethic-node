defmodule Uniris.P2P.Message.NewP2PView do
  @moduledoc """
  Represents a P2P availability from a list of nodes as bit sequence
  """
  defstruct [:nodes_availability]

  @type t :: %__MODULE__{
          nodes_availability: bitstring()
        }
end
