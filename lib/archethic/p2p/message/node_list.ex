defmodule Archethic.P2P.Message.NodeList do
  @moduledoc """
  Represents a message a list of nodes
  """
  defstruct nodes: []

  alias Archethic.P2P.Node

  @type t :: %__MODULE__{
          nodes: list(Node.t())
        }
end
