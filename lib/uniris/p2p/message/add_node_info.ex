defmodule Uniris.P2P.Message.AddNodeInfo do
  @moduledoc """
  Represents a message to request to add an information in the beacon chain regarding a node

  This message is used during the node bootstraping and during the beacon P2P sampling.
  """
  @enforce_keys [:subset, :node_info]
  defstruct [:subset, :node_info]

  alias Uniris.BeaconSlot.NodeInfo

  @type t :: %__MODULE__{
          subset: binary(),
          node_info: NodeInfo.t()
        }
end
