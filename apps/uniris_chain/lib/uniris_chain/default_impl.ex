defmodule UnirisChain.DefaultImpl do
  @moduledoc false
  alias UnirisChain.Transaction
  alias __MODULE__.Store
  @behaviour UnirisChain.Impl

  @spec get_transaction(binary()) ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def get_transaction(address) do
    Store.get_transaction(address)
  end

  @spec get_transaction_chain(binary()) ::
          {:ok, list(Transaction.validated())}
          | {:error, :transaction_chain_not_exists}
  def get_transaction_chain(address) do
    case Store.get_transaction_chain(address) do
      [] ->
        {:error, :transaction_chain_not_exists}

      chain ->
        {:ok, chain}
    end
  end

  @spec get_unspent_output_transactions(binary()) ::
          {:ok, list(Transaction.validated())} | {:error, :unspent_outputs_not_exists}
  def get_unspent_output_transactions(address) do
    case Store.get_unspent_output_transactions(address) do
      [] ->
        {:error, :unspent_outputs_not_exists}

      utxo ->
        {:ok, utxo}
    end
  end

  @spec store_transaction(Transaction.validated()) :: :ok
  def store_transaction(tx = %Transaction{}) do
    Store.store_transaction(tx)
  end

  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  def store_transaction_chain(txs) do
    Store.store_transaction_chain(txs)
  end

  @spec get_last_node_shared_secret_transaction() :: Transaction.validated()
  def get_last_node_shared_secret_transaction() do
    Store.get_last_node_shared_secret_transaction()
  end

  @spec list_device_shared_secret_transactions() :: list(Transaction.validated())
  def list_device_shared_secret_transactions() do
    Store.list_device_shared_secret_transactions()
  end
end
