defmodule Archethic.Contracts.Interpreter.Version1.Library.Contract do
  @moduledoc false

  # this alias is used to create the atom :Contract required for the AST manipulation
  alias __MODULE__.{}

  alias Archethic.TransactionChain.Transaction

  @doc """
  Set contract.data.content
  """
  @spec set_content(Transaction.t(), binary()) :: Transaction.t()
  def set_content(tx = %Transaction{}, content) when is_binary(content) do
    put_in(tx, [Access.key(:data), Access.key(:content)], content)
  end

  def set_content(tx = %Transaction{}, content) when is_integer(content) do
    put_in(tx, [Access.key(:data), Access.key(:content)], Integer.to_string(content))
  end

  def set_content(tx = %Transaction{}, content) when is_float(content) do
    put_in(tx, [Access.key(:data), Access.key(:content)], Float.to_string(content))
  end
end
