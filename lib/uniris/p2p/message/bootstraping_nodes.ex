defmodule Uniris.P2P.Message.BootstrappingNodes do
  @moduledoc """
  Represents a message with the list of closest bootstraping nodes.

  This message is used during the node bootstraping
  """
  defstruct new_seeds: [], closest_nodes: []

  alias Uniris.P2P.Node

  @type t() :: %__MODULE__{
          new_seeds: list(Node.t()),
          closest_nodes: list(Node.t())
        }
end
