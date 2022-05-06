defmodule Archethic.P2P.Message.GetTransactionSummary do
  @moduledoc """
  Represents a message to get a transaction summary from a transaction address
  """
  @enforce_keys [:address]
  defstruct [:address]

  @type t :: %__MODULE__{
          address: binary()
        }
end
