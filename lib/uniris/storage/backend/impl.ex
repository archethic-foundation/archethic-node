defmodule Uniris.Storage.BackendImpl do
  @moduledoc false

  @callback child_spec(any()) :: Supervisor.child_spec()
  @callback migrate() :: :ok
  @callback get_transaction(address :: binary(), fields :: list()) ::
              {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  @callback get_transaction_chain(binary(), fields :: list()) :: list(Transaction.t())
  @callback write_transaction(Transaction.t()) :: :ok
  @callback write_transaction_chain(list(Transaction.t())) :: :ok
  @callback list_transactions(fields :: list()) :: Enumerable.t()
  @callback list_transaction_chains_info() ::
              list({last_transaction_address :: binary(), size :: non_neg_integer()})
  @callback list_transactions_by_type(type :: Transaction.type(), fields :: list()) ::
              Enumerable.t()
end
