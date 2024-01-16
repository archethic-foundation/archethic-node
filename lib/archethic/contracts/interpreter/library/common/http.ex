defmodule Archethic.Contracts.Interpreter.Library.Common.Http do
  @moduledoc false

  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Library.Common.HttpImpl

  use Knigge, otp_app: :archethic, default: HttpImpl, delegate_at_runtime?: true

  @callback request(String.t()) :: map()
  @callback request(String.t(), String.t()) :: map()
  @callback request(String.t(), String.t(), map()) :: map()
  @callback request(String.t(), String.t(), map(), String.t() | nil) :: map()
  @callback request(String.t(), String.t(), map(), String.t() | nil, boolean()) :: map()
  @callback request_many(list(map())) :: list(map())
  @callback request_many(list(map()), boolean()) :: list(map())

  def check_types(:request, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:request, [first, second]) do
    check_types(:request, [first]) && binary_or_variable_or_function?(second)
  end

  def check_types(:request, [first, second, third]) do
    check_types(:request, [first, second]) && map_or_variable_or_function?(third)
  end

  def check_types(:request, [first, second, third, fourth]) do
    check_types(:request, [first, second, third]) && binary_or_variable_or_function?(fourth)
  end

  def check_types(:request, [first, second, third, fourth, fifth]) do
    check_types(:request, [first, second, third, fourth]) &&
      boolean_or_variable_or_function?(fifth)
  end

  def check_types(:request_many, [first]) do
    list_or_variable_or_function?(first)
  end

  def check_types(:request_many, [first, second]) do
    check_types(:request_many, [first]) && boolean_or_variable_or_function?(second)
  end

  def check_types(_, _), do: false

  defp binary_or_variable_or_function?(arg) do
    AST.is_binary?(arg) || AST.is_variable_or_function_call?(arg)
  end

  defp list_or_variable_or_function?(arg) do
    AST.is_list?(arg) || AST.is_variable_or_function_call?(arg)
  end

  defp map_or_variable_or_function?(arg) do
    AST.is_map?(arg) || AST.is_variable_or_function_call?(arg)
  end

  defp boolean_or_variable_or_function?(arg) do
    AST.is_boolean?(arg) || AST.is_variable_or_function_call?(arg)
  end
end
