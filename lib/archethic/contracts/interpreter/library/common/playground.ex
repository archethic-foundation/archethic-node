defmodule Archethic.Contracts.Interpreter.Library.Common.Playground do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.Logs

  @spec print(any()) :: nil
  def print(term) do
    Logs.append(term)
    nil
  end

  def check_types(:print, [_first]), do: true

  def check_types(_, _), do: false
end
