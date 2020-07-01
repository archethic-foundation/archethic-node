defmodule UnirisCore.P2P.Message.GetBootstrappingNodes do
  @enforce_keys [:patch]
  defstruct [:patch]

  @type t() :: %__MODULE__{
          patch: binary()
        }
end
