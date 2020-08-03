defmodule Uniris.P2P.Message.Balance do
  @moduledoc """
  Represents a message the balance of a transaction
  """
  defstruct uco: 0.0

  @type t :: %__MODULE__{
          uco: float()
        }
end
