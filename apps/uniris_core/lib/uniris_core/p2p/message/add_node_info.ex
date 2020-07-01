defmodule UnirisCore.P2P.Message.AddNodeInfo do
  @enforce_keys [:subset, :node_info]
  defstruct [:subset, :node_info]

  alias UnirisCore.BeaconSlot.NodeInfo

  @type t :: %__MODULE__{
          subset: binary(),
          node_info: NodeInfo.t()
        }
end
