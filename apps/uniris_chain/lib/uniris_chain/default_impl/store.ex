defmodule UnirisChain.DefaultImpl.Store do
  @moduledoc false
  alias UnirisChain.Transaction

  @behaviour __MODULE__.Impl

  @spec get_transaction(binary()) :: Transaction.validated()
  def get_transaction(address) do
    impl().get_transaction(address)
  end

  @spec get_transaction_chain(binary()) :: list(Transaction.validated())
  def get_transaction_chain(address) when is_binary(address) do
    impl().get_transaction_chain(address)
  end

  @spec get_unspent_output_transactions(binary()) :: list(Transaction.validated())
  def get_unspent_output_transactions(address) do
    impl().get_unspent_output_transactions(address)
  end

  @spec get_last_node_shared_secret_transaction() :: Transaction.validated()
  def get_last_node_shared_secret_transaction() do
    impl().get_last_node_shared_secret_transaction()
  end

  @spec list_device_shared_secret_transactions() :: list(Transaction.validated())
  def list_device_shared_secret_transactions() do
    impl().list_device_shared_secret_transactions()
  end

  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  def store_transaction_chain(txs) when is_list(txs) do
    impl().store_transaction_chain(txs)
  end

  @spec store_transaction(Transaction.t()) :: :ok
  def store_transaction(tx = %Transaction{}) do
    impl().store_transaction(tx)
  end

  defp impl() do
    Application.get_env(:uniris_chain, :store, __MODULE__.InMemoryImpl)
  end
end
