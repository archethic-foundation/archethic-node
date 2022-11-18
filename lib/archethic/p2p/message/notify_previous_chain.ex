defmodule Archethic.P2P.Message.NotifyPreviousChain do
  @moduledoc """
  Represents a message used to notify previous chain storage nodes about the last transaction address
  """

  defstruct [:address]

  @type t :: %__MODULE__{
          address: binary()
        }
end
