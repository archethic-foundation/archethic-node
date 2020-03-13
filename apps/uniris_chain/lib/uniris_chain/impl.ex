defmodule UnirisChain.Impl do
  @moduledoc false

  @callback get_transaction(binary()) ::
              {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  @callback get_transaction_chain(binary()) ::
              {:ok, list(Transaction.validated())} | {:error, :transaction_chain_not_exists}
  @callback get_unspent_output_transactions(binary()) ::
              {:ok, list(Transaction.validated())} | {:error, :unspent_outputs_not_exists}
  @callback store_transaction(Transaction.validated()) :: :ok
  @callback store_transaction_chain(list(Transaction.validated())) :: :ok
  @callback store_ko_transaction(Transaction.validated()) :: :ok
  @callback get_last_node_shared_secrets_transaction() ::
              {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
end
