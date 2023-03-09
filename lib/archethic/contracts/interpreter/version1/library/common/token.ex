defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.Token do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Version1.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Legacy

  @spec fetch_id_from_address(binary()) :: binary()
  defdelegate fetch_id_from_address(address),
    to: Legacy.Library,
    as: :get_token_id

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:fetch_id_from_address, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
