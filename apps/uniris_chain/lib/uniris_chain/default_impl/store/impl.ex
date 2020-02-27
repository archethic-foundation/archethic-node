defmodule UnirisChain.DefaultImpl.Store.Impl do
  @moduledoc false

  @callback get_transaction(binary()) :: Transaction.validated()
  @callback get_transaction_chain(binary()) :: list(Transaction.validated())
  @callback get_unspent_output_transactions(binary()) :: list(Transaction.validated())
  @callback store_transaction(Transaction.validated()) :: :ok
  @callback store_transaction_chain(list(Transaction.validated())) :: :ok
  @callback get_last_node_shared_secret_transaction() :: Transaction.validated()
  @callback list_device_shared_secret_transactions() :: list(Transaction.validated())
end
