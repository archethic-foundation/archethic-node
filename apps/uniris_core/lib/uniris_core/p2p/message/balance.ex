defmodule UnirisCore.P2P.Message.Balance do
  defstruct uco: 0.0

  @type t :: %__MODULE__{
          uco: float()
        }
end
