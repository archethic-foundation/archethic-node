defmodule UnirisValidation.Fee do
  @moduledoc false

  alias UnirisChain.Transaction

  @default 0.1

  @doc """
  Calculate the fee for a given transaction
  """
  def from_transaction(_tx = %Transaction{}) do
    @default
  end
end
