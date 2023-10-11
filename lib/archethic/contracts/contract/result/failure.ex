defmodule Archethic.Contracts.Contract.Failure do
  @moduledoc """
  This struct holds the data about an execution that failed
  """

  @enforce_keys [:user_friendly_error]
  defstruct [:user_friendly_error, :error, stacktrace: [], logs: []]

  @type t :: %__MODULE__{
          user_friendly_error: String.t(),
          error: term(),
          stacktrace: term(),
          logs: list(String.t())
        }
end
