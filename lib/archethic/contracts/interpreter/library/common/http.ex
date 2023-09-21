defmodule Archethic.Contracts.Interpreter.Library.Common.Http do
  @moduledoc false

  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Library.Common.HttpImpl

  use Knigge, otp_app: :archethic, default: HttpImpl, delegate_at_runtime?: true

  @callback request(String.t()) :: map()
  @callback request_many(list(String.t())) :: list(map())

  def check_types(:request, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:request_many, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
