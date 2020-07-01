defmodule UnirisCore.P2P.Message.BootstrappingNodes do
  defstruct new_seeds: [], closest_nodes: []

  alias UnirisCore.P2P.Node

  @type t() :: %__MODULE__{
          new_seeds: list(Node.t()),
          closest_nodes: list(Node.t())
        }
end
