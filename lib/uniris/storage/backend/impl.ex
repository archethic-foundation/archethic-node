defmodule Uniris.Storage.BackendImpl do
  @moduledoc false

  @callback get_transaction(binary()) ::
              {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  @callback get_transaction_chain(binary()) :: list(Transaction.t())
  @callback write_transaction(Transaction.t()) :: :ok
  @callback write_transaction_chain(list(Transaction.t())) :: :ok
  @callback list_transactions() :: Enumerable.t()
  @callback list_transaction_chains_info() ::
              list({last_transaction :: Transaction.t(), size :: non_neg_integer()})
end
