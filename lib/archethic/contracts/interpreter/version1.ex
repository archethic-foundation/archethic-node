defmodule Archethic.Contracts.Interpreter.Version1 do
  @moduledoc false

  alias Archethic.Contracts.ContractConditions, as: Conditions

  @spec parse(code :: binary(), {integer(), integer(), integer()}) :: {:error, binary()}
  def parse(code, {1, _, _}), do: parse_v1(code)

  @doc """
  Return true if the given conditions are valid on the given constants
  """
  @spec valid_conditions?(Conditions.t(), map()) :: bool()
  def valid_conditions?(_conditions, _constants) do
    false
  end

  defp parse_v1(code) when is_binary(code) do
    {:error, "not implemented"}
  end
end
