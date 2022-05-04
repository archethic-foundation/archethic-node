defmodule Archethic.P2P.Message.BootstrappingNodes do
  @moduledoc """
  Represents a message with the list of closest bootstrapping nodes.

  This message is used during the node bootstrapping
  """
  defstruct new_seeds: [], closest_nodes: []

  alias Archethic.P2P.Node

  @type t() :: %__MODULE__{
          new_seeds: list(Node.t()),
          closest_nodes: list(Node.t())
        }
end
