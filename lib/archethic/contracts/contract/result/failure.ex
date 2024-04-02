defmodule Archethic.Contracts.Contract.Failure do
  @moduledoc """
  This struct holds the data about an execution that failed
  """

  @enforce_keys [:user_friendly_error]
  defstruct [:user_friendly_error, :error, stacktrace: [], logs: [], data: nil]

  @type error ::
          :state_exceed_threshold
          | :trigger_not_exists
          | :execution_raise
          | :execution_timeout
          | :contract_throw
          | :function_does_not_exist
          | :function_is_private
          | :function_timeout
          | :missing_condition

  @type t :: %__MODULE__{
          user_friendly_error: String.t(),
          error: error(),
          stacktrace: term(),
          logs: list(String.t()),
          data: term()
        }
end
