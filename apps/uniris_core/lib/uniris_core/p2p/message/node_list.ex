defmodule UnirisCore.P2P.Message.NodeList do
  defstruct nodes: []

  alias UnirisCore.P2P.Node

  @type t :: %__MODULE__{
          nodes: list(Node.t())
        }
end
