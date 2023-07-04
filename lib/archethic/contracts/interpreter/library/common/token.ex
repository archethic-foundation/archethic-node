defmodule Archethic.Contracts.Interpreter.Library.Common.Token do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @callback fetch_id_from_address(binary()) :: binary()

  def fetch_id_from_address(address), do: impl().fetch_id_from_address(address)

  defp impl,
    do:
      Application.get_env(
        :archethic,
        Archethic.Contracts.Interpreter.Library.Common.Token,
        Archethic.Contracts.Interpreter.Library.Common.TokenImpl
      )

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:fetch_id_from_address, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
