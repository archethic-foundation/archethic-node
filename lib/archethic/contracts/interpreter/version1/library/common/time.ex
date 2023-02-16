defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.Time do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Version1.Library

  @doc """
  Returns current time in unix timestamp format.
  (number of seconds since epoch)
  """
  @spec now() :: integer()
  def now() do
    DateTime.utc_now() |> DateTime.to_unix()
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:now, []), do: true
  def check_types(_, _), do: false
end
