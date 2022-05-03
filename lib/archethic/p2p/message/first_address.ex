defmodule ArchEthic.P2P.Message.FirstAddress do
  @moduledoc """
  Represents a message to first address from the transaction chain
  """
  @enforce_keys [:address]
  defstruct [:address]

  @type t :: %__MODULE__{
          address: binary()
        }
end
