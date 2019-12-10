defmodule UnirisChain.TransactionStore do
  @moduledoc false
  alias UnirisChain.Transaction

  @callback get_transaction(binary()) ::
              {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  @callback get_transaction_chain(binary()) ::
              {:ok, list(Transaction.validated())}
              | {:error, :chain_not_exists}
              | {:error, :invalid_chain}

  @callback get_last_node_shared_key_transaction() :: Transaction.validated()

  @callback store_transaction_chain(list(Transaction.validated())) :: :ok

  @spec get_transaction(binary()) ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def get_transaction(address) when is_binary(address) do
    impl().get_transaction(address)
  end

  @spec get_transaction_chain(binary()) ::
          {:ok, list(Transaction.validated())}
          | {:error, :chain_not_exists}
  def get_transaction_chain(address) when is_binary(address) do
    impl().get_transaction_chain(address)
  end

  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  def store_transaction_chain(txs) when is_list(txs) do
    impl().store_transaction_chain(txs)
  end

  @spec get_last_node_shared_key_transaction() :: Transaction.validated()
  def get_last_node_shared_key_transaction() do
    impl().get_last_node_shared_key_transaction()
  end

  defp impl(), do: Application.get_env(:uniris_chain, :transaction_store)
end
