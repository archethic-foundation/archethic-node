defmodule Uniris.P2P.Message.Balance do
  @moduledoc """
  Represents a message with the balance of a transaction
  """
  defstruct uco: 0.0, nft: %{}

  @type t :: %__MODULE__{
          uco: float(),
          nft: %{binary() => float()}
        }
end
