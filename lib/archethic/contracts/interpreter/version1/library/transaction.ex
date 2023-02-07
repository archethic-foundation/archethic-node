defmodule Archethic.Contracts.Interpreter.Version1.Library.Transaction do
  @moduledoc false

  alias Archethic.TransactionChain.Transaction

  @spec set_type(Transaction.t(), binary()) :: Transaction.t()
  def set_type(tx = %Transaction{}, type)
      when type in ["transfer", "token", "hosting", "data", "contract"] do
    %{tx | type: String.to_existing_atom(type)}
  end
end
