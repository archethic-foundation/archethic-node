defmodule Archethic.P2P.Message.Balance do
  @moduledoc """
  Represents a message with the balance of a transaction
  """
  defstruct uco: 0, nft: %{}

  @type t :: %__MODULE__{
          uco: non_neg_integer(),
          nft: %{binary() => non_neg_integer()}
        }
end
