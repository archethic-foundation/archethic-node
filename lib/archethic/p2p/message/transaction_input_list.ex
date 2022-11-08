defmodule Archethic.P2P.Message.TransactionInputList do
  @moduledoc """
  Represents a message with a list of transaction inputs
  """
  defstruct inputs: [], more?: false, offset: 0

  alias Archethic.TransactionChain.VersionedTransactionInput

  @type t() :: %__MODULE__{
          inputs: list(VersionedTransactionInput.t()),
          more?: boolean(),
          offset: non_neg_integer()
        }
end
