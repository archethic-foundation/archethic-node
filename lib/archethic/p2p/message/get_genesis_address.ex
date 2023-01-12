defmodule Archethic.P2P.Message.GetGenesisAddress do
  @moduledoc """
  Represents a message to request the first address from a transaction chain
  """

  @enforce_keys [:address]
  defstruct [:address]

  @type t() :: %__MODULE__{
          address: binary()
        }
end
