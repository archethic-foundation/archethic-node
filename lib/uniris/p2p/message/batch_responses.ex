defmodule Uniris.P2P.Message.BatchResponses do
  @moduledoc """
  Represents a message to hold a set of message execution responses at once
  """
  defstruct [:responses]

  alias Uniris.P2P.Message

  @type t :: %__MODULE__{
          responses: list({index :: non_neg_integer(), response :: Message.t()})
        }
end
