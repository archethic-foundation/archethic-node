defmodule Uniris.P2P.Message.NewTransaction do
  @moduledoc """
  Represents a message to request the process of a new transaction

  This message is used locally within a node during the bootstrap
  """
  defstruct [:transaction]

  alias Uniris.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }
end
