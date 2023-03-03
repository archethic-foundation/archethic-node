defmodule Archethic.Contracts.Interpreter.Version1.ConditionValidator do
  @moduledoc """
  This is pretty much a copy of Version0.ConditionInterpreter.
  The difference is where the scope is stored (process dict VS global variable)

  """
  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.ContractConstants, as: Constants
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Version1.Scope

  require Logger

  @doc """
  Determines if the conditions of a contract are valid from the given constants
  """
  @spec valid_conditions?(Conditions.t(), map()) :: boolean()
  def valid_conditions?(conditions = %Conditions{}, constants = %{}) do
    constants =
      constants
      |> Enum.map(fn {subset, constants} ->
        {subset, Constants.stringify(constants)}
      end)
      |> Enum.into(%{})

    conditions
    |> Map.from_struct()
    |> Enum.all?(fn {field, condition} ->
      field = Atom.to_string(field)

      case validate_condition({field, condition}, constants) do
        {_, true} ->
          true

        {_, false} ->
          value = get_constant_value(constants, field)

          Logger.debug(
            "Invalid condition for `#{inspect(field)}` with the given value: `#{inspect(value)}` - condition: #{inspect(condition)}"
          )

          false
      end
    end)
  end

  defp get_constant_value(constants, field) do
    case get_in(constants, [
           Access.key("transaction", %{}),
           Access.key(field, "")
         ]) do
      "" ->
        get_in(constants, ["next", field])

      value ->
        value
    end
  end

  defp validate_condition({"origin_family", _}, _) do
    # Skip the verification
    # The Proof of Work algorithm will use this condition to verify the transaction
    {"origin_family", true}
  end

  defp validate_condition({"address", nil}, _) do
    # Skip the verification as the address changes for each transaction
    {"address", true}
  end

  defp validate_condition({"previous_public_key", nil}, _) do
    # Skip the verification as the previous public key changes for each transaction
    {"previous_public_key", true}
  end

  defp validate_condition({"timestamp", nil}, _) do
    # Skip the verification as timestamp changes for each transaction
    {"timestamp", true}
  end

  defp validate_condition({"type", nil}, %{"next" => %{"type" => "transfer"}}) do
    # Skip the verification when it's the default type
    {"type", true}
  end

  defp validate_condition({"content", nil}, %{"next" => %{"content" => ""}}) do
    # Skip the verification when it's the default type
    {"content", true}
  end

  defp validate_condition(
         {"code", nil},
         %{
           "next" => %{"code" => next_code},
           "previous" => %{"code" => prev_code}
         }
       ) do
    {"code",
     Interpreter.sanitize_code(prev_code || "") == Interpreter.sanitize_code(next_code || "")}
  end

  # Validation rules for inherit constraints
  defp validate_condition({field, nil}, %{"previous" => prev, "next" => next}) do
    {field, Map.get(prev, field) == Map.get(next, field)}
  end

  defp validate_condition({field, condition}, constants = %{"next" => next}) do
    result = evaluate_condition(condition, constants)

    if is_boolean(result) do
      {field, result}
    else
      {field, Map.get(next, field) == result}
    end
  end

  # Validation rules for incoming transaction
  defp validate_condition({field, nil}, %{"transaction" => _}) do
    # Skip the validation if no transaction conditions are provided
    {field, true}
  end

  defp validate_condition(
         {field, condition},
         constants = %{"transaction" => transaction}
       ) do
    result = evaluate_condition(condition, constants)

    if is_boolean(result) do
      {field, result}
    else
      {field, Map.get(transaction, field) == result}
    end
  end

  defp evaluate_condition(ast, constants) do
    # reset scope and set constants
    Scope.init(constants)

    {result, _} = Code.eval_quoted(ast)
    result
  end
end
