defmodule Archethic.Contracts.Interpreter.Library.Common.Time do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.Scope

  @doc """
  Returns the Unix timestamp of the trigger (it is approximately the same as current time).
  We cannot use "now" because it is not determinist.
  """
  @spec now() :: integer()
  def now() do
    Scope.read_global(["_time_now"])
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:now, []), do: true
  def check_types(_, _), do: false
end
