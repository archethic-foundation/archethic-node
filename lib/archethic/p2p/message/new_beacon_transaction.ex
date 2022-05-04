defmodule Archethic.P2P.Message.NewBeaconTransaction do
  @moduledoc """
  Represents a message for a new beacon slot transaction
  """

  @enforce_keys [:transaction]
  defstruct [:transaction]

  alias Archethic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }
end
