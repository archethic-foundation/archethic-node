defmodule Archethic.P2P.Message.ValidationError do
  @moduledoc """
  Represents an error message
  """

  defstruct [:context, :reason, :address]

  @type t :: %__MODULE__{
          context: :invalid_transaction | :network_issue,
          reason: binary(),
          address: binary()
        }
end
