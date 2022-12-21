defmodule Archethic.P2P.Message.GetTransactionChain do
  @moduledoc """
  Represents a message to request an entire transaction chain
  """
  @enforce_keys [:address]
  defstruct [:address, :paging_state, order: :asc]

  alias Archethic.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          paging_state: nil | binary(),
          order: :desc | :asc
        }
end
