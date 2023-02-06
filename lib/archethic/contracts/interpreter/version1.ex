defmodule Archethic.Contracts.Interpreter.Version1 do
  @moduledoc false

  @spec parse(code :: binary(), {integer(), integer(), integer()}) :: {:error, binary()}
  def parse(code, {1, _, _}), do: parse_v1(code)

  defp parse_v1(code) when is_binary(code) do
    {:error, "not implemented"}
  end
end
