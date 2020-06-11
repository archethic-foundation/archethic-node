defmodule UnirisCore.Storage.BackendImpl do
  @moduledoc false

  @callback get_transaction(binary()) ::
              {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  @callback get_transaction_chain(binary()) :: list(Transaction.validated())
  @callback write_transaction(Transaction.validated()) :: :ok
  @callback write_transaction_chain(list(Transaction.validated())) :: :ok
  @callback list_transactions() :: Enumerable.t()
end
