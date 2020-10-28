defmodule Uniris.P2P.Message.GetBootstrappingNodes do
  @moduledoc """
  Represents a message to list the new bootstrapping nodes for a network patch.
  The closest authorized nodes will be returned.

  This message is used during the node bootstrapping.
  """
  @enforce_keys [:patch]
  defstruct [:patch]

  @type t() :: %__MODULE__{
          patch: binary()
        }
end
