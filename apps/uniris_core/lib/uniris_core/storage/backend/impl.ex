defmodule UnirisCore.Storage.BackendImpl do
  @moduledoc false

  @callback get_transaction(binary()) ::
              {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  @callback get_transaction_chain(binary()) ::
              {:ok, list(Transaction.validated())} | {:error, :transaction_chain_not_exists}
  @callback get_unspent_output_transactions(binary()) ::
              {:ok, list(Transaction.validated())}
              | {:error, :unspent_output_transaction_not_exists}
  @callback write_transaction(Transaction.validated()) :: :ok
  @callback write_transaction_chain(list(Transaction.validated())) :: :ok
  @callback get_last_node_shared_secrets_transaction() ::
              {:ok, Transaction.validated()} | {:error, :transaction_not_exists}

  @callback list_transactions() :: list(Transaction.validated())
  @callback node_transactions() :: list(Transaction.validated())
  @callback unspent_outputs_transactions() :: list(Transaction.validated())
  @callback origin_shared_secrets_transactions() :: list(Transaction.validated())
end
