defmodule UnirisChain do
  @moduledoc """
  Uniris reduce each block in its atomic form to provide a transaction
  with its own validation evidences that will allow it to be associated with a given
  chain.s

  """
  alias UnirisChain.Transaction
  alias UnirisChain.TransactionStore

  @behaviour TransactionStore

  @doc """
  Retrieve a transaction by its address
  """
  @impl true
  @spec get_transaction(binary()) :: {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address) when is_binary(address) do
    TransactionStore.get_transaction(address)
  end

  @doc """
  Retrieve an entire chain from the last transaction
  The returned list is ordered chronologically.
  """
  @impl true
  @spec get_transaction_chain(binary()) ::
          {:ok, list(Transaction.t())} | {:error, :chain_not_exists}
  def get_transaction_chain(address) when is_binary(address) do
    TransactionStore.get_transaction_chain(address)
  end

  @doc """
  Persist a new transaction chain and ensure its whole integrity
  """
  @impl true
  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  def store_transaction_chain(txs) when is_list(txs) do
    # TODO: check before storing the transaction
    TransactionStore.store_transaction_chain(txs)
  end

  @doc """
  Retrive the latest node shared key transaction operated during
  the renewal keys.

  From this transaction we can deduct:
  - the daily nonce
  - wheel of privacy seed
  - node shared key seed
  ...
  """
  @impl true
  @spec get_last_node_shared_key_transaction() :: Transaction.validated()
  def get_last_node_shared_key_transaction() do
    TransactionStore.get_last_node_shared_key_transaction()
  end

  @doc """
  Check the validity of a transaction based on the pending transaction integrity,
  validation stamp and cross validation stamps.
  """
  @spec valid_transaction?(UnirisChain.Transaction.validated()) :: false
  def valid_transaction?(transaction = %Transaction{}) do
    case Transaction.check_pending_integrity(transaction) do
      :ok ->
        # TODO: check validation stamp and cross validation stamps
        true

      _ ->
        false
    end
  end

  @doc """
  Recursively check the validity for a transaction chain
  """
  @spec valid_transaction_chain?(list(Transaction.validated())) :: boolean
  def valid_transaction_chain?(transaction_chain) when is_list(transaction_chain) do
    do_valid_transaction_chain?(transaction_chain)
  end

  defp do_valid_transaction_chain?([transaction = %Transaction{} | []]) do
    valid_transaction?(transaction)
  end

  defp do_valid_transaction_chain?([transaction = %Transaction{} | chain]) do
    with true <- valid_transaction?(transaction),
         true <- valid_transaction?(List.first(chain)),
         true <- UnirisCrypto.hash(transaction.previous_public_key) != List.first(chain).address do
      do_valid_transaction_chain?(chain)
    end
  end

  defp do_valid_transaction_chain?([]), do: true
end
