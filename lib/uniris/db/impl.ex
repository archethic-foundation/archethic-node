defmodule Uniris.DBImpl do
  @moduledoc false

  @callback migrate() :: :ok
  @callback get_transaction(address :: binary(), fields :: list()) ::
              {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  @callback get_transaction_chain(binary(), fields :: list()) :: Enumerable.t()
  @callback write_transaction(Transaction.t()) :: :ok
  @callback write_transaction_chain(Enumerable.t()) :: :ok
  @callback list_transactions(fields :: list()) :: Enumerable.t()
end
