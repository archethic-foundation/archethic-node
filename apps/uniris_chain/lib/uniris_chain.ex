defmodule UnirisChain do
  @moduledoc """
  Uniris network is using a transaction chain reducing blockchain to its atomic form : a transaction with its own validation evidences

  """
  alias UnirisChain.Transaction

  @behaviour UnirisChain.Impl

  defdelegate child_spec(opts), to: __MODULE__.DefaultImpl

  @doc """
  Retrieve a transaction by its address
  """
  @spec get_transaction(binary()) :: {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address) do
    impl().get_transaction(address)
  end

  @doc """
  Retrieve an entire chain from the last transaction
  The returned list is ordered chronologically.
  """
  @spec get_transaction_chain(binary()) ::
          {:ok, list(Transaction.t())} | {:error, :transaction_chain_not_exists}
  def get_transaction_chain(address) do
    impl().get_transaction_chain(address)
  end

  @doc """
  Retrieve unspent outputs with destination of transfers for the given address
  """
  @spec get_unspent_output_transactions(binary()) ::
          {:ok, list(Transaction.validated())} | {:error, :unspent_outputs_not_exists}
  def get_unspent_output_transactions(address) do
    impl().get_unspent_output_transactions(address)
  end

  @doc """
  Persist only one transaction
  """
  @spec store_transaction(Transaction.t()) :: :ok
  def store_transaction(tx = %Transaction{}) do
    impl().store_transaction(tx)
  end

  @doc """
  Persist temporary a failed transaction
  """
  @spec store_ko_transaction(Transaction.t()) :: :ok
  def store_ko_transaction(tx = %Transaction{}) do
    impl().store_transaction(tx)
  end

  @doc """
  Persist a new transaction chain
  """
  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  def store_transaction_chain(txs) when is_list(txs) do
    impl().store_transaction_chain(txs)
  end

  @doc """
  Get the latest node shared secrets transaction including the required nonces
  """
  @spec get_last_node_shared_secrets_transaction() ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def get_last_node_shared_secrets_transaction() do
    impl().get_last_node_shared_secrets_transaction()
  end

  defp impl() do
    Application.get_env(:uniris_chain, :impl, __MODULE__.DefaultImpl)
  end
end
